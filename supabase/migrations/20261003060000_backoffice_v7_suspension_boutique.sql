-- Back-office Seno v7 : suspension d'une boutique par Seno, non levable par le marchand.
-- Tant que admin_suspended est vrai, is_active est forcé à false : toutes les vérifications
-- existantes (recherche, QR code, transfert) bloquent déjà la boutique sans autre changement.

alter table public.merchant_requests
  add column if not exists admin_suspended boolean not null default false,
  add column if not exists admin_suspended_reason text check (char_length(admin_suspended_reason) <= 300),
  add column if not exists admin_suspended_at timestamptz;

-- Le marchand ne peut pas écrire ces colonnes (droits d'UPDATE/INSERT par colonne déjà restreints) :
-- on le réaffirme explicitement.
revoke update (admin_suspended, admin_suspended_reason, admin_suspended_at)
  on public.merchant_requests from anon, authenticated;
revoke insert (admin_suspended, admin_suspended_reason, admin_suspended_at)
  on public.merchant_requests from anon, authenticated;

create or replace function public.enforce_admin_suspension()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.admin_suspended then
    new.is_active := false;
  end if;
  return new;
end;
$$;
revoke all on function public.enforce_admin_suspension() from public, anon, authenticated;

drop trigger if exists merchant_admin_suspension on public.merchant_requests;
create trigger merchant_admin_suspension
  before insert or update on public.merchant_requests
  for each row execute function public.enforce_admin_suspension();
