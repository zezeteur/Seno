-- Suivi du solde de la boutique Jèko : relevé toutes les 5 min par admin-reports (mode alerts),
-- alerte email sous un seuil (sans solde, les reversements échouent).

create table if not exists public.jeko_soldes (
  id bigint generated always as identity primary key,
  montant integer,          -- FCFA ; null si la lecture a échoué
  erreur text,
  created_at timestamptz not null default now()
);
create index if not exists jeko_soldes_created_idx on public.jeko_soldes (created_at desc);
alter table public.jeko_soldes enable row level security;
revoke all on table public.jeko_soldes from anon, authenticated;

alter table public.report_settings
  add column if not exists seuil_solde_jeko integer not null default 100000 check (seuil_solde_jeko between 0 and 100000000);

-- ---------- Alertes : v8 + solde Jèko bas / illisible ----------
create or replace function public.admin_alert_conditions()
returns table (key text, message text)
language sql
stable
security definer
set search_path = ''
as $$
  with s as (select * from public.report_settings where id = 1),
  solde as (select montant, erreur, created_at from public.jeko_soldes order by created_at desc limit 1)
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
   where x.statut = 'erreur'
  union all
  select 'solde_jeko',
         format('Solde Jèko bas : %s FCFA (seuil %s FCFA), les reversements risquent d''échouer',
                solde.montant, s.seuil_solde_jeko)
    from solde, s
   where solde.montant is not null
     and solde.montant < s.seuil_solde_jeko
     and solde.created_at > now() - interval '30 minutes'
  union all
  select 'solde_jeko_illisible', format('Solde Jèko illisible : %s', coalesce(solde.erreur, '?'))
    from solde
   where solde.montant is null
     and solde.created_at > now() - interval '30 minutes';
$$;
revoke all on function public.admin_alert_conditions() from public, anon, authenticated;
