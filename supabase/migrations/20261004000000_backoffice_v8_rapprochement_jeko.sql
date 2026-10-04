-- Back-office Seno v8 : rapprochement quotidien Seno ↔ Jèko (Edge Function `jeko-reconciliation`).
-- Chaque jour à 6 h (heure d'Abidjan = UTC), les transferts créés la veille sont comparés aux
-- opérations Jèko (GET /transactions) ; les écarts sont enregistrés et signalés par email.
-- Prérequis : secrets Vault `project_url` et `cron_secret`, secrets Jèko de la fonction.

-- ---------- Exécutions (une ligne par jour rapproché, écrasée si on relance) ----------
create table if not exists public.rapprochements (
  jour date primary key,
  statut text not null default 'en_cours' check (statut in ('en_cours', 'ok', 'ecarts', 'erreur')),
  transferts_seno integer not null default 0,
  operations_jeko integer not null default 0,
  rapproches integer not null default 0,
  ecarts integer not null default 0,
  volume_seno bigint not null default 0,   -- FCFA : collectes confirmées côté Seno
  volume_jeko bigint not null default 0,   -- FCFA : paiements Seno réussis côté Jèko
  erreur text,
  started_at timestamptz not null default now(),
  finished_at timestamptz
);
alter table public.rapprochements enable row level security;
revoke all on table public.rapprochements from anon, authenticated;

-- ---------- Écarts détectés ----------
create table if not exists public.rapprochement_ecarts (
  id uuid primary key default gen_random_uuid(),
  jour date not null references public.rapprochements (jour) on delete cascade,
  type text not null check (type in (
    'collecte_manquante',           -- Seno a confirmé le paiement, aucun paiement réussi chez Jèko
    'collecte_non_traitee',         -- Paiement réussi chez Jèko, envoi Seno resté en attente / échoué
    'reversement_manquant',         -- Seno « réussi », aucun reversement réussi chez Jèko
    'reversement_non_enregistre',   -- Reversement réussi chez Jèko, envoi Seno non « réussi »
    'double_reversement',           -- Plusieurs reversements réussis pour un même envoi
    'remboursement_manquant',       -- Seno « remboursé », aucun remboursement réussi chez Jèko
    'remboursement_non_enregistre', -- Remboursement réussi chez Jèko, envoi Seno non « remboursé »
    'reversement_et_remboursement', -- Destinataire payé ET expéditeur remboursé
    'montant_different',            -- Montant Jèko ≠ montant attendu
    'operation_inconnue'            -- Opération Jèko sans envoi Seno correspondant
  )),
  transfert_id uuid references public.transferts (id) on delete set null,
  jeko_id text,
  reference text,
  montant_seno bigint,
  montant_jeko bigint,
  statut_seno text,
  statut_jeko text,
  detail text not null,
  resolu_at timestamptz,
  resolu_par uuid,
  note text,
  created_at timestamptz not null default now()
);
create index if not exists rapprochement_ecarts_jour_idx on public.rapprochement_ecarts (jour);
create index if not exists rapprochement_ecarts_ouverts_idx on public.rapprochement_ecarts (jour) where resolu_at is null;
create index if not exists rapprochement_ecarts_transfert_idx on public.rapprochement_ecarts (transfert_id);
alter table public.rapprochement_ecarts enable row level security;
revoke all on table public.rapprochement_ecarts from anon, authenticated;

-- ---------- Alertes : v4 + écarts non résolus / rapprochement en erreur ----------
create or replace function public.admin_alert_conditions()
returns table (key text, message text)
language sql
stable
security definer
set search_path = ''
as $$
  with s as (select * from public.report_settings where id = 1)
  select 'incidents', format('%s transfert(s) à traiter manuellement', n)
    from (select count(*) n from public.transferts
           where statut in ('transfert_echec', 'remboursement_echec')) x, s
   where x.n >= s.seuil_incidents
  union all
  select 'reseau:' || r.id,
         format('%s : %s %% d''échecs sur la dernière heure (%s/%s transferts)',
                r.nom, round(100.0 * x.ko / x.total), x.ko, x.total)
    from (select reseau_destination, count(*) total,
                 count(*) filter (where statut in ('transfert_echec', 'remboursement_echec', 'rembourse',
                                                    'rembourse_en_cours', 'reversement_relance')) ko
            from public.transferts
           where created_at > now() - interval '1 hour'
             and statut not in ('collecte_en_attente', 'collecte_echec')
           group by reseau_destination) x
    join public.reseaux r on r.id = x.reseau_destination, s
   where x.total >= s.min_transferts_reseau
     and 100.0 * x.ko / x.total >= s.seuil_taux_echec
  union all
  select 'relances_bloquees', format('%s reversement(s) en attente de relance depuis plus de 10 min', n)
    from (select count(*) n from public.transferts
           where statut = 'reversement_relance' and prochaine_tentative < now() - interval '10 minutes') x
   where x.n > 0
  union all
  select 'reversements_lents', format('%s reversement(s) « en cours » depuis plus de 30 min', n)
    from (select count(*) n from public.transferts
           where statut = 'transfert_en_cours' and updated_at < now() - interval '30 minutes') x
   where x.n > 0
  union all
  select 'silence', format('Aucun transfert réussi depuis %s minutes', s.silence_minutes)
    from s
   where extract(hour from now() at time zone 'UTC') between 7 and 21
     and exists (select 1 from public.transferts where created_at > now() - interval '7 days')
     and not exists (select 1 from public.transferts
                      where statut = 'reussi'
                        and updated_at > now() - make_interval(mins => s.silence_minutes))
  union all
  select 'rapprochement', format('Rapprochement Jèko : %s écart(s) non résolu(s)', n)
    from (select count(*) n from public.rapprochement_ecarts where resolu_at is null) x
   where x.n > 0
  union all
  select 'rapprochement_erreur',
         format('Rapprochement Jèko du %s en erreur : %s', to_char(jour, 'DD/MM'), coalesce(erreur, '?'))
    from (select jour, statut, erreur from public.rapprochements order by jour desc limit 1) x
   where x.statut = 'erreur';
$$;
revoke all on function public.admin_alert_conditions() from public, anon, authenticated;

-- ---------- Résolution d'un écart (note + audit dans la même transaction) ----------
create or replace function public.admin_resolve_ecart(p_id uuid, p_admin uuid, p_note text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from public.admins where user_id = p_admin and role = 'admin') then
    raise exception 'forbidden';
  end if;
  if length(trim(coalesce(p_note, ''))) < 5 then raise exception 'note_required'; end if;
  update public.rapprochement_ecarts
     set resolu_at = now(), resolu_par = p_admin, note = trim(p_note)
   where id = p_id and resolu_at is null;
  if not found then raise exception 'not_found'; end if;
  insert into public.admin_audit_log (admin_id, action, target_type, target_id, details)
  values (p_admin, 'rapprochement.resolve', 'ecart', p_id::text, jsonb_build_object('note', trim(p_note)));
end;
$$;
revoke all on function public.admin_resolve_ecart(uuid, uuid, text) from public, anon, authenticated;

-- ---------- Planification ----------
create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.unschedule(jobname) from cron.job where jobname = 'jeko-reconciliation';

-- 6 h, avant le rapport quotidien de 8 h : rapproche la veille
select cron.schedule('jeko-reconciliation', '0 6 * * *', $cron$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
           || '/functions/v1/jeko-reconciliation',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000);
$cron$);

-- Relance d'un jour précis depuis le back-office, sans exposer le secret cron
create or replace function public.admin_run_reconciliation(p_jour date)
returns bigint
language sql
security definer
set search_path = ''
as $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
           || '/functions/v1/jeko-reconciliation',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')),
    body := jsonb_build_object('jour', p_jour),
    timeout_milliseconds := 120000);
$$;
revoke all on function public.admin_run_reconciliation(date) from public, anon, authenticated;
