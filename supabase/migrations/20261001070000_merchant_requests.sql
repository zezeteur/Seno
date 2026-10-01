-- Demandes pour devenir marchand (une par utilisateur)
create table if not exists public.merchant_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  business_name text not null check (char_length(business_name) between 2 and 80),
  category text not null,
  description text check (char_length(description) <= 300),
  city text not null,
  address text not null,
  business_phone text not null,
  email text,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  created_at timestamptz not null default now()
);

alter table public.merchant_requests enable row level security;

create policy "merchant_requests_select_own" on public.merchant_requests
  for select to authenticated using ((select auth.uid()) = user_id);

-- Insertion uniquement en statut pending ; la validation se fait côté admin
create policy "merchant_requests_insert_own" on public.merchant_requests
  for insert to authenticated
  with check ((select auth.uid()) = user_id and status = 'pending');
