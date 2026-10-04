-- Back-office Seno v4 : rapport quotidien et alertes par email (Edge Function `admin-reports`).
-- Prérequis : secrets Vault `project_url` et `cron_secret` (déjà créés pour retry-payouts),
-- secrets de la fonction : RESEND_API_KEY, REPORTS_FROM (ex. "Seno <alertes@seno.ci>").

-- ---------- Réglages (une seule ligne, modifiée depuis Paramètres) ----------
create table if not exists public.report_settings (
  id smallint primary key default 1 check (id = 1),
  recipients text[] not null default '{}',
  daily_enabled boolean not null default true,
  alerts_enabled boolean not null default true,
  seuil_incidents integer not null default 1 check (seuil_incidents >= 1),
  seuil_taux_echec integer not null default 20 check (seuil_taux_echec between 1 and 100),
  min_transferts_reseau integer not null default 10 check (min_transferts_reseau >= 1),
  silence_minutes integer not null default 120 check (silence_minutes >= 15),
  updated_at timestamptz not null default now()
);
insert into public.report_settings (id) values (1) on conflict do nothing;
alter table public.report_settings enable row level security;
revoke all on table public.report_settings from anon, authenticated;

-- ---------- Alertes ouvertes (anti-spam : une alerte n'est envoyée qu'à l'ouverture et à la résolution) ----------
create table if not exists public.admin_alerts (
  key text primary key,                -- ex. 'incidents', 'reseau:<id>', 'silence', 'relances_bloquees'
  message text not null,
  opened_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  resolved_at timestamptz
);
alter table public.admin_alerts enable row level security;
revoke all on table public.admin_alerts from anon, authenticated;

-- ---------- Conditions d'alerte courantes ----------
create or replace function public.admin_alert_conditions()
returns table (key text, message text)
language sql
stable
security definer
set search_path = ''
as $$
  with s as (select * from public.report_settings where id = 1)
  -- Incidents à traiter manuellement
  select 'incidents', format('%s transfert(s) à traiter manuellement', n)
    from (select count(*) n from public.transferts
           where statut in ('transfert_echec', 'remboursement_echec')) x, s
   where x.n >= s.seuil_incidents
  union all
  -- Réseau en difficulté sur la dernière heure
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
  -- Relances bloquées : échéance dépassée de plus de 10 min (cron ou Jèko en panne)
  select 'relances_bloquees', format('%s reversement(s) en attente de relance depuis plus de 10 min', n)
    from (select count(*) n from public.transferts
           where statut = 'reversement_relance' and prochaine_tentative < now() - interval '10 minutes') x
   where x.n > 0
  union all
  -- Reversements en cours depuis plus de 30 min (webhook Jèko non reçu ?)
  select 'reversements_lents', format('%s reversement(s) « en cours » depuis plus de 30 min', n)
    from (select count(*) n from public.transferts
           where statut = 'transfert_en_cours' and updated_at < now() - interval '30 minutes') x
   where x.n > 0
  union all
  -- Aucun transfert réussi en journée (7 h – 22 h, heure d'Abidjan = UTC)
  select 'silence', format('Aucun transfert réussi depuis %s minutes', s.silence_minutes)
    from s
   where extract(hour from now() at time zone 'UTC') between 7 and 21
     and exists (select 1 from public.transferts where created_at > now() - interval '7 days')
     and not exists (select 1 from public.transferts
                      where statut = 'reussi'
                        and updated_at > now() - make_interval(mins => s.silence_minutes));
$$;

-- ---------- Rapport d'une journée (UTC = heure d'Abidjan) ----------
create or replace function public.admin_daily_report(p_day date default (now() at time zone 'UTC')::date - 1)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with t as (
    select * from public.transferts
     where created_at >= p_day::timestamp at time zone 'UTC'
       and created_at < (p_day + 1)::timestamp at time zone 'UTC'
  )
  select jsonb_build_object(
    'jour', p_day,
    'transferts', (select count(*) from t where statut not in ('collecte_en_attente', 'collecte_echec')),
    'reussis', (select count(*) from t where statut = 'reussi'),
    'volume', (select coalesce(sum(montant), 0) from t where statut = 'reussi'),
    'frais', (select coalesce(sum(frais), 0) from t where statut = 'reussi'),
    'paiements_abandonnes', (select count(*) from t where statut = 'collecte_echec'),
    'rembourses', (select count(*) from t where statut in ('rembourse', 'rembourse_en_cours')),
    'incidents_ouverts', (select count(*) from public.transferts
                           where statut in ('transfert_echec', 'remboursement_echec')),
    'inscrits', (select count(*) from auth.users
                  where created_at >= p_day::timestamp at time zone 'UTC'
                    and created_at < (p_day + 1)::timestamp at time zone 'UTC'),
    'nouvelles_boutiques', (select count(*) from public.merchant_requests
                             where created_at >= p_day::timestamp at time zone 'UTC'
                               and created_at < (p_day + 1)::timestamp at time zone 'UTC'),
    'reseaux', coalesce((
      select jsonb_agg(x order by x.total desc) from (
        select r.nom, count(t.id) total,
               count(t.id) filter (where t.statut = 'reussi') reussis,
               coalesce(sum(t.montant) filter (where t.statut = 'reussi'), 0) volume
          from t join public.reseaux r on r.id = t.reseau_destination
         where t.statut not in ('collecte_en_attente', 'collecte_echec')
         group by r.nom) x), '[]'::jsonb)
  );
$$;

revoke all on function public.admin_alert_conditions() from public, anon, authenticated;
revoke all on function public.admin_daily_report(date) from public, anon, authenticated;

-- ---------- Planification ----------
create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.unschedule(jobname) from cron.job where jobname in ('admin-alerts', 'admin-daily-report');

-- Alertes : toutes les 5 minutes
select cron.schedule('admin-alerts', '*/5 * * * *', $cron$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
           || '/functions/v1/admin-reports',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')),
    body := '{"mode":"alerts"}'::jsonb)
  where exists (select 1 from public.report_settings
                 where id = 1 and alerts_enabled and cardinality(recipients) > 0);
$cron$);

-- Rapport quotidien : 8 h (heure d'Abidjan = UTC)
select cron.schedule('admin-daily-report', '0 8 * * *', $cron$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
           || '/functions/v1/admin-reports',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')),
    body := '{"mode":"daily"}'::jsonb)
  where exists (select 1 from public.report_settings
                 where id = 1 and daily_enabled and cardinality(recipients) > 0);
$cron$);

-- Test depuis le back-office : déclenche la fonction sans exposer le secret cron
create or replace function public.admin_send_test_report()
returns bigint
language sql
security definer
set search_path = ''
as $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
           || '/functions/v1/admin-reports',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')),
    body := '{"mode":"test"}'::jsonb);
$$;
revoke all on function public.admin_send_test_report() from public, anon, authenticated;
