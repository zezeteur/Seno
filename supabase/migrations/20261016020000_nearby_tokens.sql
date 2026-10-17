-- Envoi à proximité : jetons éphémères diffusés en BLE (identifiant de service).
-- Seule l'Edge Function `nearby` (service role) lit / écrit : aucun accès client.
create table if not exists public.nearby_tokens (
  token text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create index if not exists nearby_tokens_user_id_idx on public.nearby_tokens (user_id);
create index if not exists nearby_tokens_expires_at_idx on public.nearby_tokens (expires_at);

alter table public.nearby_tokens enable row level security;
revoke all on public.nearby_tokens from anon, authenticated;
