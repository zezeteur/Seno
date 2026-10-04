-- Back-office Seno v22 : lutte contre la fraude.
-- * fraud_settings : seuils de détection (modifiables dans le back-office)
-- * fraud_flags : détections (une par utilisateur et par règle et par 24 h)
-- * fraud_watchlist : comptes à surveiller (ajout automatique ou manuel)
-- * numeros_bloques : liste noire (envoi depuis / vers un numéro)
-- * device_accounts : historique compte ↔ appareil (token FCM), pour « plusieurs comptes sur le même appareil »
-- * user_events 'echec_code' : chaque code d'accès erroné
-- admin_fraud_scan() est lancée par admin-reports (cron `admin-alerts`, toutes les 5 min) qui envoie l'email.

-- ---------- Réglages ----------
create table if not exists public.fraud_settings (
  id int primary key default 1 check (id = 1),
  actif boolean not null default true,
  alertes_email boolean not null default true,
  rafale_envois int not null default 5 check (rafale_envois >= 2),
  rafale_minutes int not null default 10 check (rafale_minutes between 1 and 1440),
  nouveau_compte_jours int not null default 7 check (nouveau_compte_jours between 1 and 90),
  nouveau_compte_pct int not null default 80 check (nouveau_compte_pct between 10 and 100),
  comptes_par_appareil int not null default 3 check (comptes_par_appareil >= 2),
  appareil_jours int not null default 30 check (appareil_jours between 1 and 365),
  echecs_code int not null default 5 check (echecs_code >= 2),
  echecs_heures int not null default 24 check (echecs_heures between 1 and 168),
  destinataires_max int not null default 10 check (destinataires_max >= 2),
  expediteurs_max int not null default 8 check (expediteurs_max >= 2),
  updated_at timestamptz not null default now()
);
insert into public.fraud_settings (id) values (1) on conflict do nothing;

-- ---------- Détections ----------
create table if not exists public.fraud_flags (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  regle text not null,
  message text not null,
  details jsonb not null default '{}',
  notifie boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists fraud_flags_a_notifier_idx on public.fraud_flags (created_at) where not notifie;
create index if not exists fraud_flags_user_idx on public.fraud_flags (user_id, regle, created_at desc);
create index if not exists fraud_flags_created_idx on public.fraud_flags (created_at desc);

-- ---------- Comptes à surveiller ----------
create table if not exists public.fraud_watchlist (
  user_id uuid primary key references auth.users (id) on delete cascade,
  statut text not null default 'a_examiner' check (statut in ('a_examiner', 'surveille', 'classe')),
  source text not null default 'auto' check (source in ('auto', 'manuel')),
  regles text[] not null default '{}',
  motif text,
  nb_detections int not null default 0,
  derniere_detection timestamptz,
  admin_id uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists fraud_watchlist_statut_idx on public.fraud_watchlist (statut, derniere_detection desc);

-- ---------- Liste noire de numéros ----------
create table if not exists public.numeros_bloques (
  numero text primary key check (numero ~ '^\d{10}$'),
  sens text not null default 'tous' check (sens in ('envoi', 'reception', 'tous')),
  motif text not null,
  admin_id uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);

-- ---------- Appareils ----------
create table if not exists public.device_accounts (
  token text not null,
  user_id uuid not null references auth.users (id) on delete cascade,
  platform text,
  first_seen timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  primary key (token, user_id)
);
create index if not exists device_accounts_user_idx on public.device_accounts (user_id);

alter table public.fraud_settings enable row level security;
alter table public.fraud_flags enable row level security;
alter table public.fraud_watchlist enable row level security;
alter table public.numeros_bloques enable row level security;
alter table public.device_accounts enable row level security;
revoke all on table public.fraud_settings, public.fraud_flags, public.fraud_watchlist,
  public.numeros_bloques, public.device_accounts from anon, authenticated;

create or replace function public.log_device_account() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.device_accounts (token, user_id, platform)
  values (new.token, new.user_id, new.platform)
  on conflict (token, user_id) do update set last_seen = now(), platform = excluded.platform;
  return new;
exception when others then
  return new;
end $$;
drop trigger if exists log_device_account on public.push_tokens;
create trigger log_device_account after insert or update on public.push_tokens
  for each row execute function public.log_device_account();
insert into public.device_accounts (token, user_id, platform, first_seen, last_seen)
select token, user_id, platform, updated_at, updated_at from public.push_tokens
on conflict do nothing;

-- ---------- Échecs du code d'accès ----------
alter table public.user_events drop constraint if exists user_events_type_check;
alter table public.user_events add constraint user_events_type_check
  check (type in ('connexion', 'pseudo', 'blocage', 'deblocage', 'echec_code'));

create or replace function public.log_access_failure() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.failed_attempts > coalesce(old.failed_attempts, 0) then
    insert into public.user_events (user_id, type, details)
    values (new.user_id, 'echec_code', jsonb_build_object('tentative', new.failed_attempts));
  end if;
  return new;
exception when others then
  return new;
end $$;
drop trigger if exists log_access_failure on public.access_codes;
create trigger log_access_failure after update of failed_attempts on public.access_codes
  for each row execute function public.log_access_failure();

-- ---------- Enregistrement d'une détection (dédoublonnée sur 24 h) ----------
create or replace function public.fraud_flag(p_user uuid, p_regle text, p_message text, p_details jsonb default '{}')
returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from public.fraud_flags f
              where f.user_id = p_user and f.regle = p_regle and f.created_at > now() - interval '24 hours') then
    return false;
  end if;
  insert into public.fraud_flags (user_id, regle, message, details) values (p_user, p_regle, p_message, p_details);
  insert into public.fraud_watchlist as w (user_id, regles, nb_detections, derniere_detection)
  values (p_user, array[p_regle], 1, now())
  on conflict (user_id) do update set
    regles = (select array_agg(distinct r) from unnest(w.regles || p_regle) r),
    nb_detections = w.nb_detections + 1,
    derniere_detection = now(),
    -- Compte « classé » qui récidive : il revient à examiner
    statut = case when w.statut = 'classe' then 'a_examiner' else w.statut end,
    updated_at = now();
  return true;
end $$;

-- ---------- Liste noire : contrôle avant un envoi ----------
create or replace function public.numero_bloque(p_source text, p_destination text)
returns text
language sql stable security definer set search_path = '' as $$
  select case
    when exists (select 1 from public.numeros_bloques where numero = p_source and sens in ('envoi', 'tous')) then 'source'
    when exists (select 1 from public.numeros_bloques where numero = p_destination and sens in ('reception', 'tous')) then 'destination'
  end;
$$;

-- ---------- Analyse périodique : renvoie les nouvelles détections ----------
create or replace function public.admin_fraud_scan()
returns table (user_id uuid, regle text, message text)
language plpgsql security definer set search_path = '' as $$
declare
  s public.fraud_settings;
  p public.plafonds_transfert;
  r record;
begin
  select * into s from public.fraud_settings where id = 1;
  if not found or not s.actif then return; end if;
  select * into p from public.plafonds_transfert where id = 1;

  -- 1. Beaucoup d'envois en peu de temps
  for r in
    select t.expediteur u, count(*) n from public.transferts t
     where t.created_at > now() - make_interval(mins => s.rafale_minutes)
     group by 1 having count(*) >= s.rafale_envois
  loop
    message := format('%s envois en %s min', r.n, s.rafale_minutes);
    if public.fraud_flag(r.u, 'rafale', message, jsonb_build_object('envois', r.n)) then
      user_id := r.u; regle := 'rafale'; return next;
    end if;
  end loop;

  -- 2. Nouveau compte qui atteint vite ses plafonds (journalier ou mensuel)
  for r in
    select t.expediteur u,
           coalesce(sum(t.montant) filter (where t.created_at >= date_trunc('day', now())), 0) jour,
           coalesce(sum(t.montant), 0) mois
      from public.transferts t
      join auth.users au on au.id = t.expediteur
     where au.created_at > now() - make_interval(days => s.nouveau_compte_jours)
       and t.created_at >= date_trunc('month', now())
       and t.statut not in ('collecte_echec', 'collecte_en_attente', 'rembourse')
     group by 1
    having coalesce(sum(t.montant) filter (where t.created_at >= date_trunc('day', now())), 0)
             >= p.journalier * s.nouveau_compte_pct / 100.0
        or coalesce(sum(t.montant), 0) >= p.mensuel * s.nouveau_compte_pct / 100.0
  loop
    message := format('Compte de moins de %s j : %s FCFA envoyés aujourd''hui, %s FCFA ce mois (plafonds %s / %s)',
                      s.nouveau_compte_jours, r.jour, r.mois, p.journalier, p.mensuel);
    if public.fraud_flag(r.u, 'nouveau_plafond', message, jsonb_build_object('jour', r.jour, 'mois', r.mois)) then
      user_id := r.u; regle := 'nouveau_plafond'; return next;
    end if;
  end loop;

  -- 3. Plusieurs comptes sur le même appareil
  for r in
    select d.user_id u, x.n, x.token
      from (select da.token, count(distinct da.user_id) n from public.device_accounts da
             where da.last_seen > now() - make_interval(days => s.appareil_jours)
             group by da.token having count(distinct da.user_id) >= s.comptes_par_appareil) x
      join public.device_accounts d on d.token = x.token
     where d.last_seen > now() - make_interval(days => s.appareil_jours)
  loop
    message := format('%s comptes utilisés sur le même appareil', r.n);
    if public.fraud_flag(r.u, 'appareil_partage', message, jsonb_build_object('comptes', r.n, 'appareil', left(r.token, 12))) then
      user_id := r.u; regle := 'appareil_partage'; return next;
    end if;
  end loop;

  -- 4. Échecs de code d'accès en série
  for r in
    select e.user_id u, count(*) n from public.user_events e
     where e.type = 'echec_code' and e.created_at > now() - make_interval(hours => s.echecs_heures)
     group by 1 having count(*) >= s.echecs_code
  loop
    message := format('%s codes d''accès erronés en %s h', r.n, s.echecs_heures);
    if public.fraud_flag(r.u, 'echecs_code', message, jsonb_build_object('echecs', r.n)) then
      user_id := r.u; regle := 'echecs_code'; return next;
    end if;
  end loop;

  -- 5. Envois vers beaucoup de destinataires différents (24 h)
  for r in
    select t.expediteur u, count(distinct t.numero_destination) n from public.transferts t
     where t.created_at > now() - interval '24 hours'
     group by 1 having count(distinct t.numero_destination) >= s.destinataires_max
  loop
    message := format('Envois vers %s destinataires différents en 24 h', r.n);
    if public.fraud_flag(r.u, 'destinataires', message, jsonb_build_object('destinataires', r.n)) then
      user_id := r.u; regle := 'destinataires'; return next;
    end if;
  end loop;

  -- 6. Reçoit de beaucoup d'expéditeurs différents (24 h, hors boutiques) : compte « collecteur »
  for r in
    select c.proprietaire u, count(distinct t.expediteur) n from public.transferts t
      join public.comptes c on c.id = t.compte_destination
     where t.created_at > now() - interval '24 hours' and t.expediteur <> c.proprietaire
       and t.statut not in ('collecte_echec', 'collecte_en_attente')
       and not exists (select 1 from public.merchant_requests m where m.user_id = c.proprietaire and m.is_active)
     group by 1 having count(distinct t.expediteur) >= s.expediteurs_max
  loop
    message := format('Reçoit de %s expéditeurs différents en 24 h', r.n);
    if public.fraud_flag(r.u, 'expediteurs', message, jsonb_build_object('expediteurs', r.n)) then
      user_id := r.u; regle := 'expediteurs'; return next;
    end if;
  end loop;
end $$;

-- ---------- Chronologie : + échecs de code (user_events) et détections ----------
create or replace function public.admin_user_timeline(
  p_user uuid, p_limit int default 50, p_offset int default 0, p_kinds text[] default null
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
    union all
    select f.created_at, 'fraude', f.regle, jsonb_build_object('message', f.message) || f.details, null
      from public.fraud_flags f where f.user_id = p_user
  )
  select ev.created_at, ev.kind, ev.label, ev.details, ev.ref from ev
   where p_kinds is null or ev.kind = any (p_kinds)
   order by 1 desc
   limit least(greatest(p_limit, 1), 500)
  offset greatest(p_offset, 0);
$$;

revoke execute on function public.admin_user_timeline(uuid, int, int, text[]) from public, anon, authenticated;
revoke execute on function public.admin_fraud_scan() from public, anon, authenticated;
revoke execute on function public.fraud_flag(uuid, text, text, jsonb) from public, anon, authenticated;
revoke execute on function public.numero_bloque(text, text) from public, anon, authenticated;
revoke execute on function public.log_device_account() from public, anon, authenticated;
revoke execute on function public.log_access_failure() from public, anon, authenticated;
