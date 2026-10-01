-- Recherche par pseudo optimisée pour beaucoup d'utilisateurs :
-- intervalle [q, q + U+10FFFF) au lieu de LIKE (index utilisé même en plan
-- générique) et tri dans l'ordre de l'index (LIMIT s'arrête après 10 lignes).
-- Le préfixe exact (« sara ») sort naturellement avant « sara_k ».
create or replace function public.search_seno_users(p_query text)
returns table (pseudo text, avatar_url text)
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
  -- 3 à 30 caractères : pas de parcours large de la base
  if length(q) < 3 or length(q) > 30 then
    return;
  end if;

  return query
    select p.pseudo, p.avatar_url
    from public.profiles p
    where lower(p.pseudo) operator(pg_catalog.~>=~) q
      and lower(p.pseudo) operator(pg_catalog.~<~) (q || chr(1114111))
      and p.id <> auth.uid()
    order by lower(p.pseudo) using operator(pg_catalog.~<~)
    limit 10;
end;
$$;
