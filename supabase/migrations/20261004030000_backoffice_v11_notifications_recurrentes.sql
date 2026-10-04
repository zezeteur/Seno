-- Back-office Seno v11 : notifications push récurrentes (nécessite v10).
-- push_schedules : message renvoyé chaque jour / semaine / mois à heure fixe (heure d'Abidjan = UTC).
-- pg_cron appelle l'Edge Function push-recurring toutes les 5 min ; push_claim_due() réserve
-- les envois dus en avançant next_run dans la même requête (pas de double envoi).

create table if not exists public.push_schedules (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references auth.users (id),
  categorie text not null check (categorie in ('info', 'maintenance', 'promo', 'nouveaute')),
  segment text not null check (segment in ('all', 'inactive', 'merchants', 'reseau', 'user')),
  segment_param text,
  jours int not null default 30 check (jours between 1 and 365),
  titre text not null check (length(trim(titre)) between 1 and 80),
  message text not null check (length(trim(message)) between 1 and 300),
  frequence text not null check (frequence in ('daily', 'weekly', 'monthly')),
  heure time not null,
  jour_semaine smallint check (jour_semaine between 1 and 7), -- 1 = lundi (ISO)
  jour_mois smallint check (jour_mois between 1 and 28),
  actif boolean not null default true,
  next_run timestamptz not null,
  last_run timestamptz,
  created_at timestamptz not null default now(),
  check (frequence <> 'weekly' or jour_semaine is not null),
  check (frequence <> 'monthly' or jour_mois is not null)
);
create index if not exists push_schedules_due_idx on public.push_schedules (next_run) where actif;
alter table public.push_schedules enable row level security;
revoke all on table public.push_schedules from anon, authenticated;

alter table public.push_campaigns
  add column if not exists schedule_id uuid references public.push_schedules (id) on delete set null;

-- Prochaine occurrence strictement après p_from (UTC)
create or replace function public.push_next_run(
  p_frequence text, p_heure time, p_jour_semaine smallint, p_jour_mois smallint, p_from timestamptz default now()
) returns timestamptz
language plpgsql immutable set search_path = public as $$
declare
  d date := (p_from at time zone 'UTC')::date;
  candidate timestamptz;
begin
  for i in 0..62 loop
    candidate := ((d + i) + p_heure) at time zone 'UTC';
    if candidate > p_from and (
      p_frequence = 'daily'
      or (p_frequence = 'weekly' and extract(isodow from d + i) = p_jour_semaine)
      or (p_frequence = 'monthly' and extract(day from d + i) = p_jour_mois)
    ) then
      return candidate;
    end if;
  end loop;
  raise exception 'Récurrence invalide';
end;
$$;

-- Réserve les envois dus : avance next_run et renvoie les lignes à traiter
create or replace function public.push_claim_due()
returns setof public.push_schedules
language sql security definer set search_path = public as $$
  update push_schedules s
  set last_run = now(),
      next_run = push_next_run(s.frequence, s.heure, s.jour_semaine, s.jour_mois, now())
  where s.id in (
    select id from push_schedules where actif and next_run <= now() for update skip locked
  )
  returning s.*;
$$;
revoke all on function public.push_claim_due() from public, anon, authenticated;
revoke all on function public.push_next_run(text, time, smallint, smallint, timestamptz) from public, anon, authenticated;

select cron.unschedule('push-recurring') where exists (select 1 from cron.job where jobname = 'push-recurring');
select cron.schedule('push-recurring', '*/5 * * * *', $cron$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
           || '/functions/v1/push-recurring',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')),
    body := '{}'::jsonb
  );
$cron$);
