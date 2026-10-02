-- Profil : le numéro vient toujours de auth.users (vérifié par OTP), jamais du client.
-- Sinon un utilisateur pouvait prendre le numéro d'un autre et apparaître à sa place
-- dans lookup_seno_contacts. Le compte par défaut doit appartenir à l'utilisateur.
create or replace function public.enforce_profile_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_phone text;
begin
  select u.phone into v_phone from auth.users u where u.id = new.id;
  new.phone := case
    when v_phone is null or v_phone = '' then ''
    when v_phone like '+%' then v_phone
    else '+' || v_phone
  end;

  if new.default_compte_id is not null
     and (tg_op = 'INSERT' or new.default_compte_id is distinct from old.default_compte_id)
     and not exists (select 1 from public.comptes c
                      where c.id = new.default_compte_id and c.proprietaire = new.id) then
    raise exception 'invalid_default_compte' using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke all on function public.enforce_profile_integrity() from public, anon, authenticated;
revoke all on function public.enforce_pseudo_global_unique() from public, anon, authenticated;

drop trigger if exists profiles_integrity on public.profiles;
create trigger profiles_integrity
  before insert or update on public.profiles
  for each row execute function public.enforce_profile_integrity();

-- Défense en profondeur : seules les edge functions (service role) écrivent ces tables
revoke insert, update on public.transferts from anon, authenticated;
revoke insert, update on public.comptes from anon, authenticated;

-- Boutique : le client ne fixe ni l'état ni la date de changement de pseudo à la création
revoke insert on public.merchant_requests from anon, authenticated;
grant insert (user_id, business_name, pseudo, category, description, city, address,
  business_phone, email, logo_url)
  on public.merchant_requests to authenticated;
