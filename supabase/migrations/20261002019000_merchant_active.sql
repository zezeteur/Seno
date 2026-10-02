-- Boutique activée / désactivée par le marchand (page « Ma boutique »)
alter table public.merchant_requests
  add column if not exists is_active boolean not null default true;

grant update (is_active) on public.merchant_requests to authenticated;
