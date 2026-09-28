-- Changement de pseudo limité à 1 fois tous les 7 jours
alter table public.profiles
  add column if not exists pseudo_changed_at timestamptz;

create or replace function public.enforce_pseudo_cooldown()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.pseudo is distinct from old.pseudo then
    if old.pseudo_changed_at is not null
       and old.pseudo_changed_at > now() - interval '7 days' then
      raise exception 'pseudo_cooldown' using errcode = 'P0001';
    end if;
    new.pseudo_changed_at := now();
  else
    -- Le client ne peut pas modifier la date lui-même
    new.pseudo_changed_at := old.pseudo_changed_at;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_pseudo_cooldown on public.profiles;
create trigger profiles_pseudo_cooldown
  before update on public.profiles
  for each row execute function public.enforce_pseudo_cooldown();
