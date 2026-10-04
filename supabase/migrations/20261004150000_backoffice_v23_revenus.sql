-- Tableau des revenus : frais encaissés vs coûts Jèko, par période et par réseau.
-- Coût Jèko = 1,5 % par opération : un envoi réussi = collecte (sur total) + reversement
-- (sur montant), soit ~3 %. Un envoi remboursé = collecte + remboursement (sur total), sans frais encaissés.
create or replace function public.admin_revenue(
  p_granularite text default 'jour',   -- 'jour' | 'semaine' | 'mois'
  p_debut date default current_date - 29,
  p_fin date default current_date,
  p_taux numeric default 1.5
)
returns table (
  periode date,
  reseau text,
  envois bigint,
  volume bigint,
  frais bigint,
  cout_jeko bigint,
  rembourses bigint,
  cout_remboursements bigint,
  marge bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  with t as (
    select date_trunc(case p_granularite when 'mois' then 'month' when 'semaine' then 'week' else 'day' end,
                      t.created_at at time zone 'UTC')::date as periode,
           r.nom as reseau,
           t.statut, t.montant, t.frais, t.total
      from public.transferts t
      join public.reseaux r on r.id = t.reseau_destination
     where t.created_at >= p_debut::timestamp at time zone 'UTC'
       and t.created_at < (p_fin + 1)::timestamp at time zone 'UTC'
       and t.statut in ('reussi', 'rembourse')
  ), agg as (
    select periode, reseau,
           count(*) filter (where statut = 'reussi') as envois,
           coalesce(sum(montant) filter (where statut = 'reussi'), 0) as volume,
           coalesce(sum(frais) filter (where statut = 'reussi'), 0) as frais,
           round(coalesce(sum(total + montant) filter (where statut = 'reussi'), 0) * p_taux / 100) as cout_jeko,
           count(*) filter (where statut = 'rembourse') as rembourses,
           round(coalesce(sum(2 * total) filter (where statut = 'rembourse'), 0) * p_taux / 100) as cout_remb
      from t
     group by periode, reseau
  )
  select periode, reseau, envois, volume, frais,
         cout_jeko::bigint, rembourses, cout_remb::bigint,
         (frais - cout_jeko - cout_remb)::bigint
    from agg
   order by periode desc, reseau;
$$;
revoke all on function public.admin_revenue(text, date, date, numeric) from public, anon, authenticated;
