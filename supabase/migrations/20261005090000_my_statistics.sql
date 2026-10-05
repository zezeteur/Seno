-- Statistiques de l'utilisateur sur une période : totaux, dépenses par jour
-- et par catégorie. Seuls les transferts réussis comptent ; un envoi vers un
-- de ses propres comptes n'est ni une dépense ni un revenu.
create or replace function public.get_my_statistics(
  p_from timestamptz,
  p_to timestamptz,
  p_tz text default 'Africa/Abidjan'
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with sent as (
    select t.total as amount, t.created_at,
           -- Boutique : sa catégorie ; personne ou numéro externe : transfert
           case when m.user_id is not null
                then coalesce(m.category, 'other') else 'transfer' end as category
    from public.transferts t
    left join public.comptes c on c.id = t.compte_destination
    left join public.merchant_requests m
      on m.user_id = c.proprietaire and c.proprietaire <> auth.uid()
    where t.expediteur = auth.uid()
      and t.statut = 'reussi'
      and c.proprietaire is distinct from auth.uid()
      and t.created_at >= p_from and t.created_at < p_to
  ),
  received as (
    select t.montant as amount, t.created_at
    from public.transferts t
    join public.comptes c on c.id = t.compte_destination
    where c.proprietaire = auth.uid()
      and t.expediteur <> auth.uid()
      and t.statut = 'reussi'
      and t.created_at >= p_from and t.created_at < p_to
  ),
  daily as (
    select (created_at at time zone p_tz)::date as day,
           sum(amount) filter (where kind = 'in') as income,
           sum(amount) filter (where kind = 'out') as expenses
    from (
      select amount, created_at, 'out' as kind from sent
      union all
      select amount, created_at, 'in' from received
    ) x
    group by 1
  )
  select jsonb_build_object(
    'income', (select coalesce(sum(amount), 0) from received),
    'expenses', (select coalesce(sum(amount), 0) from sent),
    'daily', coalesce((
      select jsonb_agg(jsonb_build_object(
               'day', day,
               'income', coalesce(income, 0),
               'expenses', coalesce(expenses, 0)) order by day)
      from daily), '[]'::jsonb),
    'categories', coalesce((
      select jsonb_agg(jsonb_build_object(
               'category', category, 'amount', amount, 'count', n)
             order by amount desc)
      from (select category, sum(amount) as amount, count(*) as n
            from sent group by category) g), '[]'::jsonb)
  );
$$;

revoke all on function public.get_my_statistics(timestamptz, timestamptz, text)
  from public, anon;
grant execute on function public.get_my_statistics(timestamptz, timestamptz, text)
  to authenticated;
