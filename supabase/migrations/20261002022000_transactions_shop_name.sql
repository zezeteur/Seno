-- Historique : nom de la boutique en plus (titre des transactions vers un marchand)
drop function if exists public.get_my_transactions(integer, timestamptz, text);
create function public.get_my_transactions(
  p_limit integer default 50,
  p_before timestamptz default null,
  p_sens text default null
)
returns table (id uuid, sens text, label text, avatar_url text, montant integer,
  frais integer, statut text, created_at timestamptz, montant_recu integer,
  numero text, reseau_id uuid, payment_url text, merchant_category text,
  merchant_name text)
language sql
stable
security definer
set search_path = ''
as $$
  select * from (
    select t.id, 'envoi' as sens,
           coalesce(m.pseudo, p.pseudo, t.destinataire_label),
           case when m.user_id is not null then m.logo_url else p.avatar_url end,
           t.total, t.frais, t.statut, t.created_at,
           t.montant,
           case when c.proprietaire is not null and c.proprietaire <> auth.uid()
                then left(t.numero_destination, 2) || ' •• •• '
                     || substr(t.numero_destination, 7, 2) || ' '
                     || substr(t.numero_destination, 9, 2)
                else t.numero_destination end,
           t.reseau_destination,
           case when t.statut = 'collecte_en_attente' then t.jeko_redirect_url end,
           m.category,
           m.business_name
    from public.transferts t
    left join public.comptes c on c.id = t.compte_destination
    left join public.profiles p on p.id = c.proprietaire
    -- Marchand (paiement à soi-même exclu) : la boutique remplace le profil
    left join public.merchant_requests m
      on m.user_id = c.proprietaire and c.proprietaire <> auth.uid()
    where t.expediteur = auth.uid()
      and (p_sens is null or p_sens = 'envoi')
      and (p_before is null or t.created_at < p_before)

    union all

    select t.id, 'reception', p.pseudo, p.avatar_url,
           t.montant, 0, t.statut, t.created_at,
           t.montant, t.numero_destination, t.reseau_destination, null,
           null, null
    from public.transferts t
    join public.comptes c on c.id = t.compte_destination
    join public.profiles p on p.id = t.expediteur
    where c.proprietaire = auth.uid()
      and t.expediteur <> auth.uid()
      and t.statut = 'reussi'
      and (p_sens is null or p_sens = 'reception')
      and (p_before is null or t.created_at < p_before)
  ) x
  order by 8 desc
  limit least(greatest(p_limit, 1), 200);
$$;

revoke all on function public.get_my_transactions(integer, timestamptz, text) from public, anon;
grant execute on function public.get_my_transactions(integer, timestamptz, text) to authenticated;
