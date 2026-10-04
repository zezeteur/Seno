-- Back-office Seno v5 : statistiques par boutique.
-- Un paiement à une boutique = transfert réussi vers un compte appartenant au marchand,
-- envoyé par quelqu'un d'autre (même règle que get_my_transactions dans l'app).

create index if not exists transferts_compte_destination_idx
  on public.transferts (compte_destination, created_at) where statut = 'reussi';

-- Classement des boutiques sur une période (p_days null = depuis le début).
-- Toutes les boutiques : l'app les rend visibles dès is_active, quel que soit status.
create or replace function public.admin_merchant_stats(p_days integer default 30)
returns table (
  id uuid, user_id uuid, business_name text, pseudo text, category text, city text,
  status text, is_active boolean, logo_url text,
  paiements bigint, clients bigint, volume bigint, panier_moyen integer,
  dernier_paiement timestamptz, volume_precedent bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  with p as (
    select c.proprietaire as marchand, t.expediteur, t.montant, t.created_at
      from public.transferts t
      join public.comptes c on c.id = t.compte_destination
     where t.statut = 'reussi'
       and t.expediteur <> c.proprietaire
       and (p_days is null or t.created_at > now() - make_interval(days => p_days * 2))
  )
  select m.id, m.user_id, m.business_name, m.pseudo, m.category, m.city,
         m.status, m.is_active, m.logo_url,
         count(p.*) filter (where p_days is null or p.created_at > now() - make_interval(days => p_days)),
         count(distinct p.expediteur) filter (where p_days is null or p.created_at > now() - make_interval(days => p_days)),
         coalesce(sum(p.montant) filter (where p_days is null or p.created_at > now() - make_interval(days => p_days)), 0),
         (avg(p.montant) filter (where p_days is null or p.created_at > now() - make_interval(days => p_days)))::integer,
         max(p.created_at),
         -- Période précédente de même durée (évolution)
         case when p_days is null then null
              else coalesce(sum(p.montant) filter (where p.created_at <= now() - make_interval(days => p_days)), 0) end
    from public.merchant_requests m
    left join p on p.marchand = m.user_id
   group by m.id
   order by 12 desc, m.business_name;
$$;

-- Détail d'une boutique : volume quotidien, meilleurs clients, derniers paiements
create or replace function public.admin_merchant_detail(p_merchant uuid, p_days integer default 30)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with m as (select * from public.merchant_requests where id = p_merchant),
  p as (
    select t.id, t.expediteur, t.montant, t.created_at, t.numero_destination
      from public.transferts t
      join public.comptes c on c.id = t.compte_destination
      join m on m.user_id = c.proprietaire
     where t.statut = 'reussi'
       and t.expediteur <> c.proprietaire
       and t.created_at > now() - make_interval(days => p_days)
  )
  select jsonb_build_object(
    'jours', (select coalesce(jsonb_agg(jsonb_build_object('jour', d::date, 'volume', coalesce(v.volume, 0),
                                                            'nombre', coalesce(v.nombre, 0)) order by d), '[]')
                from generate_series(current_date - (p_days - 1), current_date, interval '1 day') d
                left join (select created_at::date jour, sum(montant) volume, count(*) nombre
                             from p group by 1) v on v.jour = d::date),
    'clients', (select coalesce(jsonb_agg(x order by x.volume desc), '[]') from (
                  select p.expediteur as id, pr.pseudo, pr.prenoms, pr.nom,
                         count(*) as paiements, sum(p.montant) as volume
                    from p left join public.profiles pr on pr.id = p.expediteur
                   group by p.expediteur, pr.pseudo, pr.prenoms, pr.nom
                   order by sum(p.montant) desc limit 10) x),
    'derniers', (select coalesce(jsonb_agg(x order by x.created_at desc), '[]') from (
                   select p.id, p.montant, p.created_at, pr.pseudo
                     from p left join public.profiles pr on pr.id = p.expediteur
                    order by p.created_at desc limit 15) x),
    'heures', (select coalesce(jsonb_agg(jsonb_build_object('heure', h, 'nombre', coalesce(n, 0)) order by h), '[]')
                 from generate_series(0, 23) h
                 left join (select extract(hour from created_at)::int hh, count(*) n from p group by 1) x on x.hh = h)
  );
$$;

revoke all on function public.admin_merchant_stats(integer) from public, anon, authenticated;
revoke all on function public.admin_merchant_detail(uuid, integer) from public, anon, authenticated;
