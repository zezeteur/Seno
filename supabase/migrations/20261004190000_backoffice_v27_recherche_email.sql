-- Équipe : recherche directe d'un compte Auth par email (remplace le parcours paginé de listUsers,
-- limité à 10 000 comptes). GoTrue enregistre les emails en minuscules : égalité exacte = index utilisé.
create or replace function public.admin_find_user_by_email(p_email text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select id
    from auth.users
   where email = lower(trim(p_email))
     and deleted_at is null
   order by is_sso_user, created_at
   limit 1;
$$;
revoke all on function public.admin_find_user_by_email(text) from public, anon, authenticated;
