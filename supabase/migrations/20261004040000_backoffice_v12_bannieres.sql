-- Back-office Seno v12 : bannières d'information affichées dans l'app (ex. « Orange Money en maintenance ce soir »).
-- Écrites par le back-office (service role) ; lues par l'app : uniquement les bannières actives
-- dans leur période d'affichage.

create table if not exists public.app_banners (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references auth.users (id),
  message text not null check (length(trim(message)) between 3 and 200),
  niveau text not null default 'info' check (niveau in ('info', 'warning', 'critical')),
  -- Réseau concerné : la bannière n'est montrée qu'aux utilisateurs ayant un compte sur ce réseau
  reseau_id uuid references public.reseaux (id) on delete cascade,
  lien text check (lien is null or lien ~ '^https://'),
  fermable boolean not null default true,
  debut timestamptz not null default now(),
  fin timestamptz,
  actif boolean not null default true,
  created_at timestamptz not null default now(),
  check (fin is null or fin > debut)
);
create index if not exists app_banners_actives_idx on public.app_banners (debut, fin) where actif;
alter table public.app_banners enable row level security;
revoke all on table public.app_banners from anon, authenticated;
grant select on table public.app_banners to authenticated;

drop policy if exists "app_banners_visibles" on public.app_banners;
create policy "app_banners_visibles" on public.app_banners
  for select to authenticated
  using (
    actif and debut <= now() and (fin is null or fin > now())
    and (
      reseau_id is null
      or exists (select 1 from public.comptes c where c.proprietaire = (select auth.uid()) and c.id_reseau = reseau_id)
    )
  );
