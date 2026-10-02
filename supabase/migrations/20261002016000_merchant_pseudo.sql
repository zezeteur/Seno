-- Pseudo unique de la boutique. Même espace que les pseudos utilisateurs
-- (on paie un @pseudo) : ni un autre commerce ni un utilisateur ne peut l'avoir.
alter table public.merchant_requests add column if not exists pseudo text
  check (pseudo ~ '^[a-z0-9]{3,20}$');
create unique index if not exists merchant_requests_pseudo_key
  on public.merchant_requests (lower(pseudo));

create or replace function public.is_pseudo_available(p_pseudo text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not exists (
    select 1 from public.profiles where lower(pseudo) = lower(p_pseudo)
  ) and not exists (
    select 1 from public.merchant_requests where lower(pseudo) = lower(p_pseudo)
  );
$$;
