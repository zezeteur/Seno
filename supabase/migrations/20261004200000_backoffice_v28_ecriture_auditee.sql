-- Écriture + audit dans UNE transaction (comme admin_resolve_transfert) : si l'audit échoue,
-- l'écriture est annulée, et inversement. Utilisée par toutes les actions du back-office qui
-- ne touchent que la base. Tables autorisées en liste blanche ; colonnes passées en
-- identifiants (%I) et valeurs en paramètres, typées par jsonb_populate_record.
create or replace function public.admin_audited_write(
  p_admin uuid,
  p_table text,
  p_op text,                       -- 'insert' | 'update' | 'upsert' | 'delete'
  p_values jsonb default '{}',     -- colonnes à écrire (insert / update / upsert)
  p_match jsonb default '{}',      -- égalités WHERE (update / delete) ; colonnes de conflit (upsert)
  p_action text default null,
  p_target_type text default null,
  p_target_id text default null,   -- défaut : id de la première ligne écrite
  p_details jsonb default '{}'
)
returns jsonb                      -- lignes écrites (tableau)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tables constant text[] := array[
    'admins', 'app_banners', 'fraud_settings', 'fraud_watchlist', 'frais_transfert',
    'merchant_requests', 'numeros_bloques', 'objectifs_mensuels', 'plafonds_transfert',
    'profiles', 'push_schedules', 'report_settings', 'reseaux', 'support_contacts', 'user_notes'
  ];
  v_cols text;
  v_set text;
  v_where text;
  v_conflict text;
  v_sql text;
  v_rows jsonb;
begin
  if not (p_table = any (v_tables)) then
    raise exception 'table_not_allowed' using errcode = '42501';
  end if;
  if not exists (select 1 from public.admins where user_id = p_admin) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_action is null or p_target_type is null then
    raise exception 'audit_required' using errcode = '22023';
  end if;

  select string_agg(format('%I', k), ', ' order by k) into v_cols from jsonb_object_keys(p_values) k;
  select string_agg(format('t.%1$I is not distinct from m.%1$I', k), ' and ') into v_where
    from jsonb_object_keys(p_match) k;

  if p_op = 'insert' then
    if v_cols is null then raise exception 'values_required' using errcode = '22023'; end if;
    v_sql := format(
      'with w as (insert into public.%1$I as t (%2$s) select %2$s from jsonb_populate_record(null::public.%1$I, $1) returning to_jsonb(t) j)
       select coalesce(jsonb_agg(j), ''[]'') from w', p_table, v_cols);

  elsif p_op = 'upsert' then
    if v_cols is null or p_match = '{}' then raise exception 'values_required' using errcode = '22023'; end if;
    select string_agg(format('%I', k), ', ') into v_conflict from jsonb_object_keys(p_match) k;
    select string_agg(format('%1$I = excluded.%1$I', k), ', ') into v_set
      from jsonb_object_keys(p_values) k where not p_match ? k;
    v_sql := format(
      'with w as (insert into public.%1$I as t (%2$s) select %2$s from jsonb_populate_record(null::public.%1$I, $1)
                  on conflict (%3$s) do %4$s returning to_jsonb(t) j)
       select coalesce(jsonb_agg(j), ''[]'') from w',
      p_table, v_cols, v_conflict, coalesce('update set ' || v_set, 'nothing'));

  elsif p_op = 'update' then
    if v_cols is null or v_where is null then raise exception 'values_required' using errcode = '22023'; end if;
    select string_agg(format('%1$I = v.%1$I', k), ', ') into v_set from jsonb_object_keys(p_values) k;
    v_sql := format(
      'with w as (update public.%1$I as t set %2$s
                    from jsonb_populate_record(null::public.%1$I, $1) v, jsonb_populate_record(null::public.%1$I, $2) m
                   where %3$s returning to_jsonb(t) j)
       select coalesce(jsonb_agg(j), ''[]'') from w', p_table, v_set, v_where);

  elsif p_op = 'delete' then
    if v_where is null then raise exception 'values_required' using errcode = '22023'; end if;
    v_sql := format(
      'with w as (delete from public.%1$I as t using jsonb_populate_record(null::public.%1$I, $2) m
                   where %2$s returning to_jsonb(t) j)
       select coalesce(jsonb_agg(j), ''[]'') from w', p_table, v_where);

  else
    raise exception 'invalid_op' using errcode = '22023';
  end if;

  execute v_sql into v_rows using p_values, p_match;

  if p_op in ('update', 'delete') and jsonb_array_length(v_rows) = 0 then
    raise exception 'not_found' using errcode = 'P0002';
  end if;

  insert into public.admin_audit_log (admin_id, action, target_type, target_id, details)
  values (p_admin, p_action, p_target_type, coalesce(p_target_id, v_rows -> 0 ->> 'id', ''), coalesce(p_details, '{}'));

  return v_rows;
end;
$$;
revoke all on function public.admin_audited_write(uuid, text, text, jsonb, jsonb, text, text, text, jsonb)
  from public, anon, authenticated;
