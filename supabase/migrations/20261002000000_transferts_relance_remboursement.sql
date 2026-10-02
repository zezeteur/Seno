-- Reversement échoué : relances automatiques, puis remboursement intégral
-- (montant + frais) vers le numéro source si l'échec persiste.
alter table public.transferts drop constraint transferts_statut_check;
alter table public.transferts add constraint transferts_statut_check check (statut in (
  'collecte_en_attente',  -- en attente de validation par l'expéditeur
  'collecte_echec',       -- paiement refusé / abandonné
  'transfert_en_cours',   -- fonds collectés, reversement lancé
  'reussi',
  'reversement_relance',  -- reversement refusé par Jèko, nouvelle tentative programmée
  'rembourse_en_cours',   -- échec définitif : remboursement de `total` lancé
  'rembourse',
  'remboursement_echec',  -- remboursement refusé : traitement manuel
  'transfert_echec'       -- issue incertaine (réseau, 5xx) : traitement manuel
));

alter table public.transferts
  add column tentatives_reversement integer not null default 0,
  add column prochaine_tentative timestamptz,
  add column jeko_refund_id text unique;

create index transferts_relance_idx on public.transferts (prochaine_tentative)
  where statut = 'reversement_relance';

-- Réserve les relances dues : un seul worker les prend (skip locked)
create or replace function public.claim_reversements_relance(p_limit integer default 20)
returns setof uuid
language sql
security definer
set search_path = ''
as $$
  update public.transferts t
     set statut = 'transfert_en_cours', prochaine_tentative = null, updated_at = now()
   where t.id in (
     select id from public.transferts
      where statut = 'reversement_relance' and prochaine_tentative <= now()
      order by prochaine_tentative
      limit p_limit
      for update skip locked
   )
  returning t.id;
$$;

revoke all on function public.claim_reversements_relance(integer) from public, anon, authenticated;

-- Plafonds : les envois remboursés (ou en cours de remboursement) ne comptent plus
create or replace function public.insert_transfert_plafonne(
  p_expediteur uuid,
  p_compte_source uuid,
  p_numero_source text,
  p_compte_destination uuid,
  p_destinataire_label text,
  p_numero_destination text,
  p_reseau_destination uuid,
  p_montant integer,
  p_frais integer,
  p_total integer,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_plafonds public.plafonds_transfert;
  v_jour timestamptz := date_trunc('day', now() at time zone 'UTC') at time zone 'UTC';
  v_mois timestamptz := date_trunc('month', now() at time zone 'UTC') at time zone 'UTC';
  v_journalier bigint;
  v_mensuel bigint;
  v_id uuid;
begin
  perform pg_advisory_xact_lock(hashtextextended('plafond:' || p_expediteur::text, 0));

  select * into strict v_plafonds from public.plafonds_transfert where id = 1;
  if p_montant > v_plafonds.par_transaction then
    return jsonb_build_object('error', 'limit_exceeded', 'limit', 'transaction');
  end if;

  select coalesce(sum(montant) filter (where created_at >= v_jour), 0),
         coalesce(sum(montant), 0)
    into v_journalier, v_mensuel
    from public.transferts
   where expediteur = p_expediteur
     and statut not in ('collecte_echec', 'rembourse_en_cours', 'rembourse')
     and created_at >= v_mois;

  if v_journalier + p_montant > v_plafonds.journalier then
    return jsonb_build_object('error', 'limit_exceeded', 'limit', 'daily');
  end if;
  if v_mensuel + p_montant > v_plafonds.mensuel then
    return jsonb_build_object('error', 'limit_exceeded', 'limit', 'monthly');
  end if;

  insert into public.transferts (
    expediteur, compte_source, numero_source, compte_destination, destinataire_label,
    numero_destination, reseau_destination, montant, frais, total, idempotency_key
  ) values (
    p_expediteur, p_compte_source, p_numero_source, p_compte_destination, p_destinataire_label,
    p_numero_destination, p_reseau_destination, p_montant, p_frais, p_total, p_idempotency_key
  )
  returning id into v_id;

  return jsonb_build_object('id', v_id);
end;
$$;

create or replace function public.get_my_plafond_usage()
returns table (journalier bigint, mensuel bigint)
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(sum(montant) filter (
           where created_at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC'), 0),
         coalesce(sum(montant), 0)
    from public.transferts
   where expediteur = (select auth.uid())
     and statut not in ('collecte_echec', 'rembourse_en_cours', 'rembourse')
     and created_at >= date_trunc('month', now() at time zone 'UTC') at time zone 'UTC';
$$;

-- Relances : la fonction `retry-payouts` est appelée chaque minute s'il y a du travail.
-- Prérequis (hors migration, une fois) :
--   select vault.create_secret('https://<ref>.supabase.co', 'project_url');
--   select vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'cron_secret');

-- Vérifie le secret envoyé par pg_cron (lu dans le Vault, jamais exposé)
create or replace function public.check_cron_secret(p_secret text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from vault.decrypted_secrets
                  where name = 'cron_secret' and decrypted_secret = p_secret);
$$;

revoke all on function public.check_cron_secret(text) from public, anon, authenticated;

create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.schedule(
  'retry-payouts',
  '* * * * *',
  $cron$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
           || '/functions/v1/retry-payouts',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')
    ),
    body := '{}'::jsonb
  )
  where exists (select 1 from public.transferts
                 where statut = 'reversement_relance' and prochaine_tentative <= now());
  $cron$
);
