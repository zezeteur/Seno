-- Contacts du répertoire ayant un compte Seno : pseudo et photo uniquement.
-- security definer : profiles reste protégé par RLS, seules ces colonnes sortent.
create or replace function public.lookup_seno_contacts(p_phones text[])
returns table (phone text, pseudo text, avatar_url text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  -- Limite l'énumération massive de numéros
  if coalesce(array_length(p_phones, 1), 0) > 2000 then
    raise exception 'too_many_phones' using errcode = '22023';
  end if;

  return query
    select p.phone, p.pseudo, p.avatar_url
    from public.profiles p
    where p.phone = any (p_phones)
      and p.id <> auth.uid()
      and p.pseudo is not null;
end;
$$;

revoke all on function public.lookup_seno_contacts(text[]) from public, anon;
grant execute on function public.lookup_seno_contacts(text[]) to authenticated;
