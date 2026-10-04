-- Back-office Seno v20 : historique complet d'un utilisateur.
-- Journal user_events (connexions, changements de pseudo, blocages / déblocages du code d'accès)
-- alimenté par triggers, et chronologie unifiée admin_user_timeline (service role uniquement).

create table if not exists public.user_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  type text not null check (type in ('connexion', 'pseudo', 'blocage', 'deblocage')),
  details jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index if not exists user_events_user_idx on public.user_events (user_id, created_at desc);
alter table public.user_events enable row level security;
revoke all on table public.user_events from anon, authenticated;

-- Connexions : chaque nouvelle session Supabase Auth (ne bloque jamais la connexion)
create or replace function public.log_user_session() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.user_events (user_id, type, details)
  values (new.user_id, 'connexion', jsonb_strip_nulls(jsonb_build_object('appareil', new.user_agent, 'ip', host(new.ip))));
  return new;
exception when others then
  return new;
end $$;
drop trigger if exists log_user_session on auth.sessions;
create trigger log_user_session after insert on auth.sessions
  for each row execute function public.log_user_session();

-- Changements de pseudo (ancien → nouveau)
create or replace function public.log_pseudo_change() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.pseudo is distinct from old.pseudo then
    insert into public.user_events (user_id, type, details)
    values (new.id, 'pseudo', jsonb_build_object('ancien', old.pseudo, 'nouveau', new.pseudo));
  end if;
  return new;
end $$;
drop trigger if exists log_pseudo_change on public.profiles;
create trigger log_pseudo_change after update of pseudo on public.profiles
  for each row execute function public.log_pseudo_change();

-- Blocages / déblocages du code d'accès (par l'utilisateur ou le support)
create or replace function public.log_access_lock() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  was_locked boolean := old.permanently_locked or coalesce(old.locked_until > now(), false);
  is_locked boolean := new.permanently_locked or coalesce(new.locked_until > now(), false);
begin
  if is_locked and (not was_locked or (new.permanently_locked and not old.permanently_locked)) then
    insert into public.user_events (user_id, type, details)
    values (new.user_id, 'blocage', jsonb_strip_nulls(jsonb_build_object(
      'definitif', new.permanently_locked, 'jusqu_a', new.locked_until, 'niveau', new.lock_level)));
  elsif was_locked and not is_locked then
    insert into public.user_events (user_id, type, details) values (new.user_id, 'deblocage', '{}');
  end if;
  return new;
end $$;
drop trigger if exists log_access_lock on public.access_codes;
create trigger log_access_lock after update on public.access_codes
  for each row execute function public.log_access_lock();

-- Chronologie : envois, réceptions, événements, actions du support et notes
create or replace function public.admin_user_timeline(
  p_user uuid, p_limit int default 100, p_before timestamptz default null, p_kinds text[] default null
)
returns table (at timestamptz, kind text, label text, details jsonb, ref text)
language sql stable security definer set search_path = '' as $$
  with mes_comptes as (select id from public.comptes where proprietaire = p_user),
  ev (created_at, kind, label, details, ref) as (
    select t.created_at, 'envoi'::text, coalesce(t.destinataire_label, t.numero_destination),
           jsonb_build_object('montant', t.montant, 'frais', t.frais, 'statut', t.statut, 'numero', t.numero_destination),
           t.id::text
      from public.transferts t where t.expediteur = p_user
    union all
    select t.created_at, 'reception', coalesce('@' || pr.pseudo, t.numero_source),
           jsonb_build_object('montant', t.montant, 'statut', t.statut, 'numero', t.numero_source),
           t.id::text
      from public.transferts t
      left join public.profiles pr on pr.id = t.expediteur
     where t.compte_destination in (select id from mes_comptes) and t.expediteur <> p_user
    union all
    select e.created_at, e.type, null, e.details, null from public.user_events e where e.user_id = p_user
    union all
    select a.created_at, 'support', a.action, a.details || jsonb_build_object('admin_id', a.admin_id), a.target_id
      from public.admin_audit_log a
     where (a.target_type = 'user' and a.target_id = p_user::text and a.action <> 'user.note')
        or (a.target_type = 'transfert' and a.target_id in (
              select id::text from public.transferts
               where expediteur = p_user or compte_destination in (select id from mes_comptes)))
    union all
    select n.created_at, 'note', n.canal, jsonb_build_object('contenu', n.contenu, 'admin_id', n.admin_id), null
      from public.user_notes n where n.user_id = p_user
  )
  select ev.created_at, ev.kind, ev.label, ev.details, ev.ref from ev
   where (p_before is null or ev.created_at < p_before)
     and (p_kinds is null or ev.kind = any (p_kinds))
   order by 1 desc
   limit least(greatest(p_limit, 1), 500);
$$;
revoke execute on function public.admin_user_timeline(uuid, int, timestamptz, text[]) from public, anon, authenticated;
revoke execute on function public.log_user_session() from public, anon, authenticated;
revoke execute on function public.log_pseudo_change() from public, anon, authenticated;
revoke execute on function public.log_access_lock() from public, anon, authenticated;
