-- Back-office Seno v9 : notes internes sur un utilisateur (historique des échanges avec le support).
-- Visibles uniquement depuis le back-office (service role). Pas de modification : c'est un historique ;
-- une erreur se corrige par une nouvelle note.

create table if not exists public.user_notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  admin_id uuid not null references auth.users (id),
  canal text not null default 'note' check (canal in ('note', 'appel', 'whatsapp', 'email', 'sms')),
  contenu text not null check (length(trim(contenu)) between 3 and 2000),
  created_at timestamptz not null default now()
);
create index if not exists user_notes_user_idx on public.user_notes (user_id, created_at desc);
alter table public.user_notes enable row level security;
revoke all on table public.user_notes from anon, authenticated;
