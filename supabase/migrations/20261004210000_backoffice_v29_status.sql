-- Page publique /status : surveillance automatique des services et gestion automatique des incidents.
-- L'Edge Function status-check (pg_cron, toutes les 5 min) vérifie chaque composant, enregistre le
-- résultat, puis ouvre / met à jour / résout les incidents. Le back-office ne fait qu'afficher.
--
-- Composants : 'api', 'auth', 'sms', 'paiements', 'transferts', 'notifications', 'reseau:<ABREVIATION>'.

-- ---------- État courant de chaque composant ----------
create table if not exists public.service_status (
  service    text primary key,
  etat       text not null check (etat in ('ok', 'degrade', 'panne')),
  latence_ms integer,
  detail     text,                 -- cause technique (jamais affichée publiquement)
  checked_at timestamptz not null default now()
);
alter table public.service_status enable row level security;
revoke all on table public.service_status from anon, authenticated;

-- ---------- Historique de chaque vérification (barres 90 jours, détection des incidents) ----------
create table if not exists public.service_checks (
  id         bigint generated always as identity primary key,
  service    text not null,
  etat       text not null check (etat in ('ok', 'degrade', 'panne')),
  latence_ms integer,
  detail     text,
  checked_at timestamptz not null default now()
);
create index if not exists service_checks_service_checked_at_idx on public.service_checks (service, checked_at desc);
create index if not exists service_checks_checked_at_idx on public.service_checks (checked_at);
alter table public.service_checks enable row level security;
revoke all on table public.service_checks from anon, authenticated;

-- ---------- Incidents (ouverts et résolus automatiquement par status-check) ----------
create table if not exists public.status_incidents (
  id       uuid primary key default gen_random_uuid(),
  service  text not null,
  titre    text not null,
  gravite  text not null check (gravite in ('degrade', 'panne')),
  phase    text not null default 'enquete' check (phase in ('enquete', 'surveillance', 'resolu')),
  debut    timestamptz not null,
  fin      timestamptz,
  created_at timestamptz not null default now()
);
-- Un seul incident ouvert par composant
create unique index if not exists status_incidents_ouvert_idx on public.status_incidents (service) where phase <> 'resolu';
create index if not exists status_incidents_debut_idx on public.status_incidents (debut desc);
alter table public.status_incidents enable row level security;
revoke all on table public.status_incidents from anon, authenticated;

-- Fil des mises à jour d'un incident (affiché sur /status, comme status.claude.com)
create table if not exists public.status_incident_updates (
  id          bigint generated always as identity primary key,
  incident_id uuid not null references public.status_incidents (id) on delete cascade,
  phase       text not null check (phase in ('enquete', 'surveillance', 'resolu')),
  message     text not null,
  created_at  timestamptz not null default now()
);
create index if not exists status_incident_updates_incident_idx on public.status_incident_updates (incident_id, created_at);
alter table public.status_incident_updates enable row level security;
revoke all on table public.status_incident_updates from anon, authenticated;

-- ---------- Résumé par composant et par jour (heure d'Abidjan) ----------
create or replace function public.status_uptime(p_jours integer default 90)
returns table (service text, jour date, total integer, ok integer, degrade integer, panne integer)
language sql stable security definer set search_path = '' as $$
  select c.service,
         (c.checked_at at time zone 'Africa/Abidjan')::date as jour,
         count(*)::int,
         count(*) filter (where c.etat = 'ok')::int,
         count(*) filter (where c.etat = 'degrade')::int,
         count(*) filter (where c.etat = 'panne')::int
  from public.service_checks c
  where c.checked_at >= now() - make_interval(days => least(p_jours, 90))
  group by 1, 2
$$;
revoke all on function public.status_uptime(integer) from public, anon, authenticated;

-- ---------- Santé des transferts par opérateur (dernière heure) ----------
create or replace function public.status_transferts()
returns table (abreviation text, nom text, actif boolean, total integer, ko integer, bloques integer)
language sql stable security definer set search_path = '' as $$
  select r.abreviation, r.nom, coalesce(r.statut, false),
         count(t.id) filter (where t.created_at > now() - interval '1 hour'
                               and t.statut not in ('collecte_en_attente', 'collecte_echec'))::int,
         count(t.id) filter (where t.created_at > now() - interval '1 hour'
                               and t.statut in ('transfert_echec', 'remboursement_echec', 'rembourse',
                                                'rembourse_en_cours', 'reversement_relance'))::int,
         -- Reversements sans réponse de l'opérateur depuis plus de 30 min
         count(t.id) filter (where t.statut = 'transfert_en_cours'
                               and t.updated_at < now() - interval '30 minutes')::int
  from public.reseaux r
  left join public.transferts t on t.reseau_destination = r.id and t.created_at > now() - interval '1 day'
  group by r.id
$$;
revoke all on function public.status_transferts() from public, anon, authenticated;

-- ---------- Planification ----------
-- Purge quotidienne des vérifications au-delà de 90 jours (les incidents sont conservés)
select cron.unschedule('status-purge') where exists (select 1 from cron.job where jobname = 'status-purge');
select cron.schedule('status-purge', '30 3 * * *', $cron$
  delete from public.service_checks where checked_at < now() - interval '91 days';
$cron$);

select cron.unschedule('status-check') where exists (select 1 from cron.job where jobname = 'status-check');
select cron.schedule('status-check', '*/5 * * * *', $cron$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
           || '/functions/v1/status-check',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
$cron$);
