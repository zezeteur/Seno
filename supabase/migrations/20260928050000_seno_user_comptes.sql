-- Comptes de réception d'un utilisateur Seno (par pseudo), pour l'envoi.
-- Numéro masqué (07 •• •• 45 67) : le transfert n'utilisera que l'id du compte.
create or replace function public.get_seno_user_comptes(p_pseudo text)
returns table (id uuid, id_reseau uuid, numero_masque text, is_default boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
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
    where lower(p.pseudo) = lower(trim(both from replace(p_pseudo, '@', '')))
      and p.id <> auth.uid()
    order by c.id = p.default_compte_id desc, c.created_at;
end;
$$;

revoke all on function public.get_seno_user_comptes(text) from public, anon;
grant execute on function public.get_seno_user_comptes(text) to authenticated;
