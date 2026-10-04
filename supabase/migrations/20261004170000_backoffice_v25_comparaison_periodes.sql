-- Tableau de bord : période en cours vs précédente, à durée écoulée égale
-- (ex. lundi→mercredi 15 h contre lundi→mercredi 15 h de la semaine dernière).
create or replace function public.admin_period_compare(p_periode text default 'semaine')
returns table (
  periode text,            -- 'actuelle' | 'precedente'
  debut timestamptz,
  fin timestamptz,
  transferts bigint,
  reussis bigint,
  volume bigint,
  frais bigint,
  inscrits bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  with b as (
    select date_trunc(case when p_periode = 'mois' then 'month' else 'week' end, now() at time zone 'UTC')
             at time zone 'UTC' as debut,
           case when p_periode = 'mois' then interval '1 month' else interval '1 week' end as pas
  ), p as (
    select 'actuelle' as periode, b.debut, now() as fin from b
    union all
    select 'precedente', b.debut - b.pas, least(b.debut, b.debut - b.pas + (now() - b.debut)) from b
  )
  select p.periode, p.debut, p.fin,
         (select count(*) from public.transferts t
           where t.created_at >= p.debut and t.created_at < p.fin
             and t.statut not in ('collecte_en_attente', 'collecte_echec')),
         (select count(*) from public.transferts t
           where t.created_at >= p.debut and t.created_at < p.fin and t.statut = 'reussi'),
         (select coalesce(sum(montant), 0) from public.transferts t
           where t.created_at >= p.debut and t.created_at < p.fin and t.statut = 'reussi'),
         (select coalesce(sum(frais), 0) from public.transferts t
           where t.created_at >= p.debut and t.created_at < p.fin and t.statut = 'reussi'),
         (select count(*) from auth.users u where u.created_at >= p.debut and u.created_at < p.fin)
    from p;
$$;
revoke all on function public.admin_period_compare(text) from public, anon, authenticated;
