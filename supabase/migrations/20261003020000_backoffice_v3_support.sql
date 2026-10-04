-- Back-office Seno v3 : support (verrous, sessions, recherche), marchands, statistiques.
-- À exécuter après backoffice_v2_securite.sql. Toutes les fonctions sont réservées
-- à la service role (appelées côté serveur après requireAdmin()).

-- ---------- Sécurité d'un utilisateur : verrous du code d'accès et des OTP ----------
-- to_jsonb(ligne) : ne lit que les colonnes réellement présentes (le schéma de prod peut
-- différer des migrations du repo). Les empreintes de codes ne sont jamais renvoyées.
create or replace function public.admin_user_security(p_user uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'access', (select to_jsonb(a) - 'code_hash' - 'salt'
                 from public.access_codes a where a.user_id = p_user),
    'otp', (select to_jsonb(o) - 'code_hash'
              from public.phone_otps o
              join public.profiles p on p.id = p_user
             where o.phone in (p.phone, ltrim(p.phone, '+'))
             limit 1)
  );
$$;

-- Déblocage complet par le support (code d'accès, vérif. date de naissance, quota SMS).
-- Seules les colonnes existantes sont remises à zéro.
create or replace function public.admin_unlock_user(p_user uuid, p_admin uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_phone text;
  v_sets text;
begin
  if not exists (select 1 from public.admins where user_id = p_admin) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select string_agg(format('%I = %s', c.column_name, d.val), ', ')
    into v_sets
    from information_schema.columns c
    join (values ('failed_attempts', '0'), ('locked_until', 'null'), ('lock_level', '0'),
                 ('permanently_locked', 'false'), ('reset_failed_attempts', '0'),
                 ('reset_lock_level', '0'), ('reset_locked_until', 'null')) d(col, val)
      on d.col = c.column_name
   where c.table_schema = 'public' and c.table_name = 'access_codes';
  if v_sets is not null then
    execute format('update public.access_codes set %s where user_id = $1', v_sets) using p_user;
  end if;

  select phone into v_phone from public.profiles where id = p_user;
  if v_phone is not null and v_phone <> '' then
    select string_agg(format('%I = %s', c.column_name, d.val), ', ')
      into v_sets
      from information_schema.columns c
      join (values ('sends_in_window', '0'), ('send_window_start', 'null')) d(col, val)
        on d.col = c.column_name
     where c.table_schema = 'public' and c.table_name = 'phone_otps';
    if v_sets is not null then
      execute format('update public.phone_otps set %s where phone in ($1, ltrim($1, ''+''))', v_sets)
        using v_phone;
    end if;
  end if;

  insert into public.admin_audit_log (admin_id, action, target_type, target_id)
  values (p_admin, 'user.unlock', 'user', p_user::text);
end;
$$;

-- ---------- Sessions (appareils connectés) ----------
create or replace function public.admin_list_sessions(p_user uuid)
returns table (id uuid, created_at timestamptz, last_active_at timestamptz, user_agent text, ip text, aal text)
language sql
stable
security definer
set search_path = ''
as $$
  select s.id, s.created_at,
         coalesce(s.refreshed_at::timestamptz, s.updated_at, s.created_at),
         s.user_agent, host(s.ip), s.aal::text
    from auth.sessions s
   where s.user_id = p_user
     and (s.not_after is null or s.not_after > now())
   order by 3 desc;
$$;

-- p_session null = toutes les sessions de l'utilisateur
create or replace function public.admin_revoke_sessions(p_user uuid, p_admin uuid, p_session uuid default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not exists (select 1 from public.admins where user_id = p_admin) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  delete from auth.sessions
   where user_id = p_user and (p_session is null or id = p_session);
  get diagnostics v_count = row_count;

  insert into public.admin_audit_log (admin_id, action, target_type, target_id, details)
  values (p_admin, 'user.revoke_sessions', 'user', p_user::text,
          jsonb_build_object('session', p_session, 'count', v_count));
  return v_count;
end;
$$;

-- ---------- Marchands : motif de refus ----------
alter table public.merchant_requests add column if not exists rejection_reason text
  check (char_length(rejection_reason) <= 300);
alter table public.merchant_requests add column if not exists reviewed_at timestamptz;

-- ---------- Statistiques par réseau (tableau de bord) ----------
create or replace function public.admin_network_stats(p_days integer default 7)
returns table (reseau text, total bigint, reussis bigint, echecs bigint, volume bigint, delai_moyen_s integer)
language sql
stable
security definer
set search_path = ''
as $$
  select r.nom,
         count(t.id),
         count(t.id) filter (where t.statut = 'reussi'),
         count(t.id) filter (where t.statut in ('transfert_echec', 'remboursement_echec',
                                                'rembourse', 'rembourse_en_cours', 'reversement_relance')),
         coalesce(sum(t.montant) filter (where t.statut = 'reussi'), 0),
         (avg(extract(epoch from (t.updated_at - t.created_at)))
            filter (where t.statut = 'reussi'))::integer
    from public.reseaux r
    left join public.transferts t
      on t.reseau_destination = r.id
     and t.created_at > now() - make_interval(days => p_days)
     and t.statut <> 'collecte_en_attente'
   group by r.nom
   order by count(t.id) desc;
$$;

revoke all on function public.admin_user_security(uuid) from public, anon, authenticated;
revoke all on function public.admin_unlock_user(uuid, uuid) from public, anon, authenticated;
revoke all on function public.admin_list_sessions(uuid) from public, anon, authenticated;
revoke all on function public.admin_revoke_sessions(uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function public.admin_network_stats(integer) from public, anon, authenticated;
