-- Blocage progressif de la vérification de date de naissance :
-- 15 min, 1 h, 24 h, puis blocage définitif (déblocage par le support)
alter table public.access_codes
  add column if not exists reset_lock_level integer not null default 0;
