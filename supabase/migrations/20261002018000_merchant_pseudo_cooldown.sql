-- Pseudo boutique : changement limité à 1 fois tous les 7 jours
-- (même trigger que le pseudo utilisateur ; la date n'est pas modifiable par le client)
alter table public.merchant_requests
  add column if not exists pseudo_changed_at timestamptz;

drop trigger if exists merchant_requests_pseudo_cooldown on public.merchant_requests;
create trigger merchant_requests_pseudo_cooldown
  before update on public.merchant_requests
  for each row execute function public.enforce_pseudo_cooldown();
