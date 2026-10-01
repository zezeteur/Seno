-- Préférences de notifications de l'utilisateur (page Paramètres > Notifications)
-- Clés : push, transactions, promotions, security (booléens)
alter table public.profiles
  add column if not exists notif_prefs jsonb not null
  default '{"push": true, "transactions": true, "promotions": false, "security": true}'::jsonb;

alter table public.profiles
  drop constraint if exists profiles_notif_prefs_object;
alter table public.profiles
  add constraint profiles_notif_prefs_object
  check (jsonb_typeof(notif_prefs) = 'object');
