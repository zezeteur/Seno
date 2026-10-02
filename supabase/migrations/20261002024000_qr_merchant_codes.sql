-- QR fixe de boutique (SENO1:M:<jeton>) : une boutique n'a pas de QR dynamique.
-- Lu et écrit uniquement par l'edge function qr-code (service role).
create table if not exists public.qr_merchant_codes (
  user_id uuid primary key references auth.users (id) on delete cascade,
  token text not null unique,
  created_at timestamptz not null default now()
);

alter table public.qr_merchant_codes enable row level security;
revoke all on table public.qr_merchant_codes from anon, authenticated;
