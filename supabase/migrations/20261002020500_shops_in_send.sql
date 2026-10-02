-- Boutiques dans l'envoi d'argent : recherche, comptes de réception et frais.
-- Seules les boutiques actives sont trouvables et payables par leur pseudo.

-- Recherche : utilisateurs + boutiques actives (logo et nom de la boutique)
drop function if exists public.search_seno_users(text);
create function public.search_seno_users(p_query text)
returns table (pseudo text, avatar_url text, display_name text, is_merchant boolean,
  category text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  q text := lower(trim(both from replace(coalesce(p_query, ''), '@', '')));
begin
  if auth.uid() is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  if length(q) < 3 or length(q) > 30 then
    return;
  end if;

  return query
    select r.pseudo, r.avatar_url, r.display_name, r.is_merchant, r.category
    from (
      select p.pseudo, p.avatar_url, null::text as display_name, false as is_merchant,
             null::text as category
      from public.profiles p
      where lower(p.pseudo) operator(pg_catalog.~>=~) q
        and lower(p.pseudo) operator(pg_catalog.~<~) (q || chr(1114111))
        and p.id <> auth.uid()
      union all
      select m.pseudo, m.logo_url, m.business_name, true, m.category
      from public.merchant_requests m
      where m.is_active
        and m.pseudo is not null
        and lower(m.pseudo) operator(pg_catalog.~>=~) q
        and lower(m.pseudo) operator(pg_catalog.~<~) (q || chr(1114111))
        and m.user_id <> auth.uid()
    ) r
    order by lower(r.pseudo) using operator(pg_catalog.~<~)
    limit 10;
end;
$$;

revoke all on function public.search_seno_users(text) from public, anon;
grant execute on function public.search_seno_users(text) to authenticated;

-- Comptes de réception : un pseudo de boutique active mène aux comptes du marchand
create or replace function public.get_seno_user_comptes(p_pseudo text)
returns table (id uuid, id_reseau uuid, numero_masque text, is_default boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_pseudo text := lower(trim(both from replace(p_pseudo, '@', '')));
begin
  if auth.uid() is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  return query
    select c.id,
           c.id_reseau,
           left(c.numero, 2) || ' •• •• ' || substr(c.numero, 7, 2) || ' '
             || substr(c.numero, 9, 2),
           c.id = p.default_compte_id
    from public.profiles p
    join public.comptes c on c.proprietaire = p.id
    where (lower(p.pseudo) = v_pseudo
           or p.id = (select m.user_id from public.merchant_requests m
                      where m.is_active and lower(m.pseudo) = v_pseudo))
      and p.id <> auth.uid()
    order by c.id = p.default_compte_id desc, c.created_at;
end;
$$;

-- Destinataire marchand actif (pseudo utilisateur ou pseudo boutique) :
-- les frais sont alors payés par le marchand (même règle que transfer)
create or replace function public.is_seno_merchant(p_pseudo text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.merchant_requests m
    join public.profiles p on p.id = m.user_id
    where auth.uid() is not null
      and m.is_active
      and m.user_id <> auth.uid()
      and lower(trim(both from replace(p_pseudo, '@', ''))) in
        (lower(p.pseudo), lower(m.pseudo))
  );
$$;

revoke all on function public.is_seno_merchant(text) from public, anon;
grant execute on function public.is_seno_merchant(text) to authenticated;
