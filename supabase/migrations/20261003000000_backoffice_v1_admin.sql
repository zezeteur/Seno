-- Back-office Seno : administrateurs, journal d'audit et statistiques.
-- À appliquer sur le projet Supabase (copier dans supabase/migrations du repo Seno
-- ou exécuter dans le SQL Editor). Le back-office lit/écrit avec la service role,
-- côté serveur uniquement, après avoir vérifié que l'utilisateur est dans `admins`.

create table if not exists public.admins (
  user_id uuid primary key references auth.users (id) on delete cascade,
  role text not null default 'admin' check (role in ('admin', 'support')),
  created_at timestamptz not null default now()
);
alter table public.admins enable row level security;
revoke all on table public.admins from anon, authenticated;

create table if not exists public.admin_audit_log (
  id bigint generated always as identity primary key,
  admin_id uuid not null references auth.users (id),
  action text not null,
  target_type text not null,
  target_id text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists admin_audit_log_created_idx on public.admin_audit_log (created_at desc);
alter table public.admin_audit_log enable row level security;
revoke all on table public.admin_audit_log from anon, authenticated;

-- Indicateurs du tableau de bord (service role uniquement)
create or replace function public.admin_dashboard_stats()
returns table (
  utilisateurs bigint,
  utilisateurs_7j bigint,
  transferts_total bigint,
  transferts_reussis bigint,
  volume_reussi bigint,
  frais_encaisses bigint,
  volume_24h bigint,
  a_traiter bigint,
  marchands_en_attente bigint,
  marchands_actifs bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select count(*) from auth.users),
    (select count(*) from auth.users where created_at > now() - interval '7 days'),
    (select count(*) from public.transferts),
    (select count(*) from public.transferts where statut = 'reussi'),
    (select coalesce(sum(montant), 0) from public.transferts where statut = 'reussi'),
    (select coalesce(sum(frais), 0) from public.transferts where statut = 'reussi'),
    (select coalesce(sum(montant), 0) from public.transferts
      where statut = 'reussi' and created_at > now() - interval '24 hours'),
    (select count(*) from public.transferts
      where statut in ('transfert_echec', 'remboursement_echec')),
    (select count(*) from public.merchant_requests where status = 'pending'),
    (select count(*) from public.merchant_requests where status = 'approved' and is_active);
$$;
revoke all on function public.admin_dashboard_stats() from public, anon, authenticated;

-- Volume quotidien réussi sur N jours (graphique du tableau de bord)
create or replace function public.admin_daily_volume(p_days integer default 14)
returns table (jour date, nombre bigint, volume bigint)
language sql
stable
security definer
set search_path = ''
as $$
  select d::date,
         count(t.id),
         coalesce(sum(t.montant), 0)
    from generate_series(current_date - (p_days - 1), current_date, interval '1 day') d
    left join public.transferts t
      on t.created_at::date = d::date and t.statut = 'reussi'
   group by d
   order by d;
$$;
revoke all on function public.admin_daily_volume(integer) from public, anon, authenticated;

-- Premier administrateur : créer l'utilisateur (email + mot de passe) dans
-- Authentication > Users, puis :
-- insert into public.admins (user_id) select id from auth.users where email = 'admin@seno.ci';
