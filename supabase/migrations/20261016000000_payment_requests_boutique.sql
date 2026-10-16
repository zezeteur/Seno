-- Encaisser pour sa boutique (scan depuis la page QR de la boutique) : le
-- payeur voit le nom et le logo de la boutique au lieu du profil personnel.
-- Le pseudo personnel reste renvoyé (paiement de la demande inchangé).

alter table public.payment_requests
  add column if not exists pour_boutique boolean not null default false;

-- Historique : demandes reçues d'une boutique
drop function if exists public.get_my_transactions(integer, timestamptz, text);
create function public.get_my_transactions(
  p_limit integer default 50,
  p_before timestamptz default null,
  p_sens text default null
)
returns table (id uuid, sens text, label text, avatar_url text, montant integer,
  frais integer, statut text, created_at timestamptz, montant_recu integer,
  numero text, reseau_id uuid, payment_url text, merchant_category text,
  merchant_name text, person_name text)
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
           m.business_name,
           nullif(trim(concat_ws(' ', p.nom, p.prenoms)), '')
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
           null, null,
           nullif(trim(concat_ws(' ', p.nom, p.prenoms)), '')
    from public.transferts t
    join public.comptes c on c.id = t.compte_destination
    join public.profiles p on p.id = t.expediteur
    where c.proprietaire = auth.uid()
      and t.expediteur <> auth.uid()
      and t.statut = 'reussi'
      and (p_sens is null or p_sens = 'reception')
      and (p_before is null or t.created_at < p_before)

    union all

    -- Demandes de paiement de plus de 24 h, ou refusées (tout de suite)
    select r.id,
           case when r.payeur = auth.uid() then 'demande_recue' else 'demande_envoyee' end,
           p.pseudo,
           -- Demande reçue d'une boutique : logo et nom de la boutique
           case when bm.user_id is not null then bm.logo_url else p.avatar_url end,
           r.montant, 0,
           'demande_' || public.payment_request_statut(r.id),
           r.created_at,
           r.montant, '', c.id_reseau, null,
           bm.category, bm.business_name,
           nullif(trim(concat_ws(' ', p.nom, p.prenoms)), '')
    from public.payment_requests r
    join public.comptes c on c.id = r.compte_destination
    join public.profiles p
      on p.id = case when r.payeur = auth.uid() then r.demandeur else r.payeur end
    left join public.merchant_requests bm
      on r.pour_boutique and r.payeur = auth.uid() and bm.user_id = r.demandeur
    where auth.uid() in (r.demandeur, r.payeur)
      and (r.created_at <= now() - interval '24 hours'
           or public.payment_request_statut(r.id) = 'refusee')
      and p_sens is null
      and (p_before is null or r.created_at < p_before)
  ) x
  order by 8 desc
  limit least(greatest(p_limit, 1), 200);
$$;

revoke all on function public.get_my_transactions(integer, timestamptz, text) from public, anon;
grant execute on function public.get_my_transactions(integer, timestamptz, text) to authenticated;

-- Demandes en cours : nom de la boutique (shop_name) et son logo
drop function if exists public.get_my_payment_requests();
create function public.get_my_payment_requests()
returns table (
  id uuid, sens text, pseudo text, avatar_url text, montant integer,
  compte_destination uuid, statut text, created_at timestamptz, shop_name text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  return query
    select * from (
      select r.id,
             case when r.payeur = v_uid then 'recue' else 'envoyee' end,
             p.pseudo,
             case when m.user_id is not null then m.logo_url else p.avatar_url end,
             r.montant,
             -- Le payeur en a besoin pour l'envoi ; inutile au demandeur
             case when r.payeur = v_uid then r.compte_destination end,
             public.payment_request_statut(r.id) as statut,
             r.created_at,
             m.business_name
      from public.payment_requests r
      join public.profiles p
        on p.id = case when r.payeur = v_uid then r.demandeur else r.payeur end
      left join public.merchant_requests m
        on r.pour_boutique and r.payeur = v_uid and m.user_id = r.demandeur
      where v_uid in (r.demandeur, r.payeur)
        and r.created_at > now() - interval '24 hours'
    ) x
    where x.statut in ('en_attente', 'en_paiement')
    order by x.created_at desc
    limit 50;
end;
$$;
revoke all on function public.get_my_payment_requests() from public, anon;
grant execute on function public.get_my_payment_requests() to authenticated;
