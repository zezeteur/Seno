-- 1. Date de naissance = facteur de réinitialisation du code d'accès :
--    fixée à l'inscription, ni relisible ni modifiable par la session (seulement le support).
revoke select, update on public.profiles from anon, authenticated;
grant select (id, phone, nom, prenoms, created_at, updated_at, pseudo, avatar_url,
  default_compte_id, pseudo_changed_at, notif_prefs) on public.profiles to authenticated;
grant update (nom, prenoms, pseudo, avatar_url, notif_prefs, updated_at)
  on public.profiles to authenticated;

-- Vérification atomique (verrou de ligne) : des essais en parallèle ne contournent plus
-- le compteur. Blocage progressif 15 min, 1 h, 24 h, puis définitif.
create or replace function public.check_reset_birth_date(p_user uuid, p_date date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c_max constant integer := 3;
  c_steps constant integer[] := array[15 * 60, 60 * 60, 24 * 60 * 60];
  v_access public.access_codes;
  v_date date;
  v_failed integer;
begin
  select * into v_access from public.access_codes where user_id = p_user for update;
  if not found then
    return jsonb_build_object('error', 'unauthorized');
  end if;
  if v_access.permanently_locked then
    return jsonb_build_object('error', 'blocked');
  end if;
  if v_access.reset_locked_until > now() then
    return jsonb_build_object('error', 'locked',
      'retry_in', ceil(extract(epoch from v_access.reset_locked_until - now()))::integer);
  end if;

  select date_naissance into v_date from public.profiles where id = p_user;
  if v_date is not null and v_date = p_date then
    update public.access_codes set reset_failed_attempts = 0, reset_lock_level = 0
     where user_id = p_user;
    return jsonb_build_object('ok', true);
  end if;

  v_failed := v_access.reset_failed_attempts + 1;
  if v_failed < c_max then
    update public.access_codes set reset_failed_attempts = v_failed where user_id = p_user;
    return jsonb_build_object('error', 'birth_date_invalid', 'remaining', c_max - v_failed);
  end if;
  if v_access.reset_lock_level >= array_length(c_steps, 1) then
    update public.access_codes
       set reset_failed_attempts = 0, reset_locked_until = null, permanently_locked = true
     where user_id = p_user;
    return jsonb_build_object('error', 'blocked');
  end if;
  update public.access_codes
     set reset_failed_attempts = 0,
         reset_lock_level = v_access.reset_lock_level + 1,
         reset_locked_until = now() + make_interval(secs => c_steps[v_access.reset_lock_level + 1])
   where user_id = p_user;
  return jsonb_build_object('error', 'locked', 'retry_in', c_steps[v_access.reset_lock_level + 1]);
end;
$$;

revoke all on function public.check_reset_birth_date(uuid, date) from public, anon, authenticated;

-- 2. Anti-énumération des numéros : 5000 numéros différents par 24 h et par utilisateur.
--    Relire ses propres contacts ne compte pas deux fois. Empreintes gardées 24 h seulement.
create table if not exists public.contact_lookups (
  user_id uuid not null references auth.users (id) on delete cascade,
  phone_hash bytea not null,
  first_seen timestamptz not null default now(),
  primary key (user_id, phone_hash)
);
alter table public.contact_lookups enable row level security;
revoke all on table public.contact_lookups from anon, authenticated;

create or replace function public.lookup_seno_contacts(p_phones text[])
returns table (phone text, pseudo text, avatar_url text)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  c_daily_limit constant integer := 5000;
  v_uid uuid := auth.uid();
  v_hashes bytea[];
  v_new integer;
  v_recent integer;
begin
  if v_uid is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  if coalesce(array_length(p_phones, 1), 0) > 2000 then
    raise exception 'too_many_phones' using errcode = '22023';
  end if;

  -- Un appel à la fois par utilisateur : pas de contournement du quota en parallèle
  perform pg_advisory_xact_lock(hashtextextended('lookup:' || v_uid::text, 0));
  delete from public.contact_lookups
   where user_id = v_uid and first_seen < now() - interval '24 hours';

  v_hashes := array(select distinct extensions.digest(x, 'sha256')
                      from unnest(p_phones) x where x is not null);
  select count(*) into v_new from unnest(v_hashes) h
   where not exists (select 1 from public.contact_lookups c
                      where c.user_id = v_uid and c.phone_hash = h);
  select count(*) into v_recent from public.contact_lookups where user_id = v_uid;
  if v_new > 0 and v_new + v_recent > c_daily_limit then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;

  insert into public.contact_lookups (user_id, phone_hash)
    select v_uid, h from unnest(v_hashes) h
  on conflict do nothing;

  return query
    select p.phone, p.pseudo, p.avatar_url
    from public.profiles p
    where p.phone = any (p_phones)
      and p.id <> v_uid
      and p.pseudo is not null;
end;
$$;
