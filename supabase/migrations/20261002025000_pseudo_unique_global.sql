-- Pseudos utilisateurs et boutiques dans le même espace, imposé par la base :
-- is_pseudo_available n'est qu'une aide côté app, contournable via l'API.

create or replace function public.enforce_pseudo_global_unique()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.pseudo is null then
    return new;
  end if;
  -- Verrou par pseudo : deux insertions concurrentes ne passent pas toutes les deux
  perform pg_advisory_xact_lock(hashtextextended('pseudo:' || lower(new.pseudo), 0));

  if tg_table_name = 'merchant_requests' then
    if exists (select 1 from public.profiles
                where lower(pseudo) = lower(new.pseudo) and id <> new.user_id) then
      raise exception 'pseudo_taken' using errcode = '23505';
    end if;
  else
    if exists (select 1 from public.merchant_requests
                where lower(pseudo) = lower(new.pseudo) and user_id <> new.id) then
      raise exception 'pseudo_taken' using errcode = '23505';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists merchant_requests_pseudo_global_unique on public.merchant_requests;
create trigger merchant_requests_pseudo_global_unique
  before insert or update of pseudo on public.merchant_requests
  for each row execute function public.enforce_pseudo_global_unique();

drop trigger if exists profiles_pseudo_global_unique on public.profiles;
create trigger profiles_pseudo_global_unique
  before insert or update of pseudo on public.profiles
  for each row execute function public.enforce_pseudo_global_unique();

-- Un pseudo mène à un seul propriétaire : l'utilisateur d'abord, sinon la boutique.
-- (Avant : un OR pouvait renvoyer les comptes de deux personnes différentes.)
create or replace function public.get_seno_user_comptes(p_pseudo text)
returns table (id uuid, id_reseau uuid, numero_masque text, is_default boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_pseudo text := lower(trim(both from replace(p_pseudo, '@', '')));
  v_owner uuid;
begin
  if auth.uid() is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  select p.id into v_owner from public.profiles p where lower(p.pseudo) = v_pseudo;
  if v_owner is null then
    select m.user_id into v_owner from public.merchant_requests m where lower(m.pseudo) = v_pseudo;
  end if;
  if v_owner is null or v_owner = auth.uid() then
    return;
  end if;

  return query
    select c.id,
           c.id_reseau,
           left(c.numero, 2) || ' •• •• ' || substr(c.numero, 7, 2) || ' '
             || substr(c.numero, 9, 2),
           c.id = p.default_compte_id
    from public.profiles p
    join public.comptes c on c.proprietaire = p.id
    where p.id = v_owner
    order by c.id = p.default_compte_id desc, c.created_at;
end;
$$;
