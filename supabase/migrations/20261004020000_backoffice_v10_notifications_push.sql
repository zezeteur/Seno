-- Back-office Seno v10 : notifications push ciblées (FCM).
-- push_tokens : un token FCM par appareil, enregistré par l'app (RLS : chacun gère les siens).
-- push_campaigns : historique des envois du back-office (service role uniquement).
-- push_audience() : résout un segment en tokens, en respectant notif_prefs.

create table if not exists public.push_tokens (
  token text primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  platform text not null check (platform in ('android', 'ios')),
  updated_at timestamptz not null default now()
);
create index if not exists push_tokens_user_idx on public.push_tokens (user_id);
alter table public.push_tokens enable row level security;

drop policy if exists "push_tokens_own" on public.push_tokens;
create policy "push_tokens_own" on public.push_tokens
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create table if not exists public.push_campaigns (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references auth.users (id),
  categorie text not null check (categorie in ('info', 'maintenance', 'promo', 'nouveaute')),
  segment text not null,
  segment_param text,
  titre text not null check (length(trim(titre)) between 1 and 80),
  message text not null check (length(trim(message)) between 1 and 300),
  destinataires int not null default 0,
  envoyes int not null default 0,
  echecs int not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists push_campaigns_created_idx on public.push_campaigns (created_at desc);
alter table public.push_campaigns enable row level security;
revoke all on table public.push_campaigns from anon, authenticated;

-- Segments : all | inactive (aucun transfert depuis p_days jours) | merchants | reseau (p_param = id réseau)
-- | user (p_param = id utilisateur). Promos/nouveautés exigent notif_prefs.promotions = true ;
-- tout envoi exige notif_prefs.push <> false. Un envoi à une personne ignore seulement "promotions".
create or replace function public.push_audience(
  p_segment text, p_param text default null, p_categorie text default 'info', p_days int default 30
) returns table (token text, user_id uuid)
language sql stable security definer set search_path = public as $$
  select t.token, t.user_id
  from push_tokens t
  join profiles p on p.id = t.user_id
  where coalesce((p.notif_prefs ->> 'push')::boolean, true)
    and (
      p_categorie not in ('promo', 'nouveaute') or p_segment = 'user'
      or coalesce((p.notif_prefs ->> 'promotions')::boolean, false)
    )
    and case p_segment
      when 'all' then true
      when 'inactive' then p.created_at < now() - make_interval(days => p_days)
        and not exists (
          select 1 from transferts tr
          where tr.expediteur = p.id and tr.created_at > now() - make_interval(days => p_days)
        )
      when 'merchants' then exists (
          select 1 from merchant_requests m where m.user_id = p.id and m.status = 'approved'
        )
      when 'reseau' then exists (
          select 1 from comptes c where c.proprietaire = p.id and c.id_reseau::text = p_param
        )
      when 'user' then p.id::text = p_param
      else false
    end;
$$;
revoke all on function public.push_audience(text, text, text, int) from public, anon, authenticated;
