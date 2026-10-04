-- Objectif de volume mensuel (FCFA réussis), suivi sur le tableau de bord.
create table if not exists public.objectifs_mensuels (
  mois date primary key check (mois = date_trunc('month', mois)::date),  -- 1er du mois
  volume_cible bigint not null check (volume_cible > 0),
  updated_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now()
);
alter table public.objectifs_mensuels enable row level security;
revoke all on table public.objectifs_mensuels from anon, authenticated;

-- Progression du mois en cours (heure d'Abidjan = UTC) : volume réussi à date et objectif
create or replace function public.admin_objectif_progress()
returns table (mois date, volume_cible bigint, volume bigint, jours_ecoules integer, jours_total integer)
language sql
stable
security definer
set search_path = ''
as $$
  with m as (select date_trunc('month', now() at time zone 'UTC')::date as d)
  select m.d,
         o.volume_cible,
         (select coalesce(sum(t.montant), 0) from public.transferts t
           where t.statut = 'reussi'
             and t.created_at >= m.d::timestamp at time zone 'UTC')::bigint,
         extract(day from now() at time zone 'UTC')::integer,
         extract(day from m.d + interval '1 month' - interval '1 day')::integer
    from m
    left join public.objectifs_mensuels o on o.mois = m.d;
$$;
revoke all on function public.admin_objectif_progress() from public, anon, authenticated;
