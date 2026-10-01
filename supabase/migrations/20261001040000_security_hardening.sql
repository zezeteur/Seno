-- Durcissement sécurité (revue du 2026-10-01)

-- ---------- 1. Profil : champs sensibles non modifiables par le client ----------
-- Le téléphone est celui du compte (e-mail interne <225…>@phone.seno.app), le
-- compte par défaut passe par set_default_compte (propriété vérifiée).
-- Les appels serveur (service role, fonctions security definer) ne sont pas concernés.
create or replace function public.protect_profile_columns()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text;
begin
  -- current_user vaut le propriétaire ici : on regarde le rôle de la requête
  if coalesce(current_setting('request.jwt.claim.role', true),
              current_setting('request.jwt.claims', true)::jsonb ->> 'role', '')
     not in ('authenticated', 'anon') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    select u.email into v_email from auth.users u where u.id = new.id;
    new.phone := case when v_email like '%@phone.seno.app'
                      then '+' || split_part(v_email, '@', 1) end;
    new.default_compte_id := null;
    new.pseudo_changed_at := null;
    new.created_at := now();
    return new;
  end if;

  new.id := old.id;
  new.phone := old.phone;
  new.created_at := old.created_at;
  -- set_default_compte (security definer) vérifie la propriété ; en direct, refusé
  if new.default_compte_id is distinct from old.default_compte_id
     and not exists (select 1 from public.comptes c
                     where c.id = new.default_compte_id and c.proprietaire = old.id) then
    new.default_compte_id := old.default_compte_id;
  end if;
  return new;
end;
$$;

revoke all on function public.protect_profile_columns() from public, anon, authenticated;

drop trigger if exists a_profiles_protect_columns on public.profiles;
-- Préfixe « a_ » : s'exécute avant profiles_pseudo_cooldown (ordre alphabétique)
create trigger a_profiles_protect_columns
  before insert or update on public.profiles
  for each row execute function public.protect_profile_columns();

-- ---------- 2. Code d'accès : essais réservés de façon atomique ----------
-- Un essai est consommé AVANT la vérification du code : au plus 5 vérifications
-- par fenêtre, même avec des requêtes simultanées.
-- Le 5e essai pose un verrou provisoire (30 s) remplacé par le vrai blocage ou
-- levé si le code est bon : pas de compte coincé si la fonction échoue entre-temps.
create or replace function public.claim_access_attempt(p_user uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.access_codes;
begin
  update public.access_codes
     set failed_attempts = case when locked_until is not null and failed_attempts >= 5
                                then 1 else failed_attempts + 1 end,
         locked_until = case when (case when locked_until is not null and failed_attempts >= 5
                                        then 1 else failed_attempts + 1 end) >= 5
                             then now() + interval '30 seconds' else null end
   where user_id = p_user
     and not permanently_locked
     and (locked_until is null or locked_until <= now())
     -- 5 essais atteints sans verrou : seulement après expiration du verrou provisoire
     and (failed_attempts < 5 or locked_until is not null)
  returning * into v_row;

  if found then
    return jsonb_build_object('attempt', v_row.failed_attempts,
                              'code_hash', v_row.code_hash, 'salt', v_row.salt);
  end if;

  select * into v_row from public.access_codes where user_id = p_user;
  if not found then
    return jsonb_build_object('error', 'not_found');
  end if;
  if v_row.permanently_locked then
    return jsonb_build_object('error', 'blocked');
  end if;
  return jsonb_build_object('error', 'locked', 'retry_in',
    greatest(1, ceil(extract(epoch from (coalesce(v_row.locked_until, now()) - now())))::int));
end;
$$;

-- Code faux. Au 5e essai : 15 min, 1 h, puis 24 h ; blocage définitif seulement
-- si p_allow_permanent (utilisateur connecté), jamais sur la connexion anonyme
-- (sinon n'importe qui pourrait bloquer un compte à partir du seul numéro).
create or replace function public.fail_access_attempt(
  p_user uuid, p_attempt int, p_allow_permanent boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_level int;
  v_steps int[] := array[15 * 60, 60 * 60, 24 * 60 * 60];
  v_seconds int;
begin
  if p_attempt < 5 then
    return jsonb_build_object('error', 'access_code_invalid', 'remaining', 5 - p_attempt);
  end if;

  select lock_level into v_level from public.access_codes where user_id = p_user for update;

  if v_level >= array_length(v_steps, 1) and p_allow_permanent then
    update public.access_codes
       set failed_attempts = 0, locked_until = null, permanently_locked = true
     where user_id = p_user;
    return jsonb_build_object('error', 'blocked');
  end if;

  v_seconds := v_steps[least(v_level + 1, array_length(v_steps, 1))];
  update public.access_codes
     set failed_attempts = 0,
         lock_level = least(v_level + 1, array_length(v_steps, 1)),
         locked_until = now() + make_interval(secs => v_seconds)
   where user_id = p_user;
  return jsonb_build_object('error', 'locked', 'retry_in', v_seconds);
end;
$$;

revoke all on function public.claim_access_attempt(uuid) from public, anon, authenticated;
revoke all on function public.fail_access_attempt(uuid, int, boolean) from public, anon, authenticated;

-- ---------- 3. OTP SMS : essais et envois atomiques ----------
alter table public.phone_otps
  add column if not exists send_window_start timestamptz,
  add column if not exists sends_in_window int not null default 0;

-- Réserve un essai (5 max par code) avant comparaison du code
create or replace function public.claim_otp_attempt(p_phone text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.phone_otps;
begin
  update public.phone_otps
     set attempts = attempts + 1
   where phone = p_phone and expires_at > now() and attempts < 5
  returning * into v_row;
  if found then
    return jsonb_build_object('code_hash', v_row.code_hash);
  end if;

  select * into v_row from public.phone_otps where phone = p_phone;
  if found and v_row.expires_at > now() then
    -- Essais épuisés : code invalidé, la ligne garde le compteur d'envois
    update public.phone_otps set expires_at = now() where phone = p_phone;
    return jsonb_build_object('error', 'too_many_attempts');
  end if;
  return jsonb_build_object('error', 'code_expired');
end;
$$;

-- Code accepté : invalidé sans effacer le compteur d'envois
create or replace function public.consume_otp(p_phone text)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.phone_otps set expires_at = now() where phone = p_phone;
$$;

-- Autorise un envoi : 1 SMS / 30 s et 5 SMS / heure par numéro.
-- Le nouvel OTP remet les essais à 0 : sans plafond horaire, redemander un SMS
-- toutes les 30 s donnerait 5 essais neufs à chaque fois.
create or replace function public.claim_otp_send(p_phone text)
returns int  -- 0 = autorisé, sinon secondes à attendre
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.phone_otps;
begin
  insert into public.phone_otps (phone, code_hash, expires_at, attempts, created_at,
                                 send_window_start, sends_in_window)
  values (p_phone, '', now(), 5, now() - interval '1 hour', null, 0)
  on conflict (phone) do nothing;

  select * into v_row from public.phone_otps where phone = p_phone for update;

  if v_row.created_at > now() - interval '30 seconds' then
    return greatest(1, ceil(extract(epoch from (v_row.created_at + interval '30 seconds' - now())))::int);
  end if;

  if v_row.send_window_start is null or v_row.send_window_start <= now() - interval '1 hour' then
    update public.phone_otps
       set send_window_start = now(), sends_in_window = 1, created_at = now()
     where phone = p_phone;
    return 0;
  end if;

  if v_row.sends_in_window >= 5 then
    return greatest(1, ceil(extract(epoch from (v_row.send_window_start + interval '1 hour' - now())))::int);
  end if;

  update public.phone_otps
     set sends_in_window = sends_in_window + 1, created_at = now()
   where phone = p_phone;
  return 0;
end;
$$;

revoke all on function public.claim_otp_attempt(text) from public, anon, authenticated;
revoke all on function public.consume_otp(text) from public, anon, authenticated;
revoke all on function public.claim_otp_send(text) from public, anon, authenticated;
