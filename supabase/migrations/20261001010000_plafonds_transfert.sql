-- Plafonds d'envoi, identiques pour tous les comptes (ligne unique id = 1).
-- Montants en FCFA, sur le montant reçu par le destinataire (hors frais).
create table public.plafonds_transfert (
  id smallint primary key default 1 check (id = 1),
  par_transaction integer not null check (par_transaction > 0),
  journalier integer not null check (journalier > 0),
  mensuel integer not null check (mensuel > 0),
  updated_at timestamptz not null default now()
);

insert into public.plafonds_transfert (par_transaction, journalier, mensuel)
values (1000000, 1500000, 5000000);

alter table public.plafonds_transfert enable row level security;

create policy "plafonds_transfert: lecture"
  on public.plafonds_transfert for select to authenticated
  using (true);

-- Cumul des envois depuis une date (envois échoués exclus)
create index if not exists transferts_cumul_idx
  on public.transferts (expediteur, created_at) where statut <> 'collecte_echec';
