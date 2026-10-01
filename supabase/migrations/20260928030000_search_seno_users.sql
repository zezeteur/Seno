-- Recherche d'utilisateurs Seno par début de pseudo : pseudo et photo uniquement.
create index if not exists profiles_pseudo_lower_idx
  on public.profiles (lower(pseudo) text_pattern_ops);

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
  -- 3 caractères minimum : pas de parcours de toute la base
  if length(q) < 3 then
    return;
  end if;
  -- Les jokers LIKE saisis sont traités comme du texte
  q := replace(replace(replace(q, '\', '\\'), '%', '\%'), '_', '\_');

  return query
    select p.pseudo, p.avatar_url
    from public.profiles p
    where lower(p.pseudo) like q || '%'
      and p.id <> auth.uid()
    order by length(p.pseudo), p.pseudo
    limit 10;
end;
$$;

revoke all on function public.search_seno_users(text) from public, anon;
grant execute on function public.search_seno_users(text) to authenticated;
