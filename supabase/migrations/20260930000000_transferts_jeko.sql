-- Envois d'argent via Jèko : collecte sur le compte de l'expéditeur
-- (demande de paiement), puis reversement au destinataire (transfert).
-- Écritures uniquement par les Edge Functions (service role).
create table public.transferts (
  id uuid primary key default gen_random_uuid(),
  expediteur uuid not null references auth.users (id),
  compte_source uuid references public.comptes (id) on delete set null,
  numero_source text not null check (numero_source ~ '^\d{10}$'),
  -- Destinataire : compte Seno, sinon numéro + réseau saisis
  compte_destination uuid references public.comptes (id) on delete set null,
  destinataire_label text not null,
  numero_destination text not null check (numero_destination ~ '^\d{10}$'),
  reseau_destination uuid not null references public.reseaux (id),
  -- Montants en FCFA : reçu par le destinataire, frais Seno, débité
  montant integer not null check (montant > 0),
  frais integer not null check (frais >= 0),
  total integer not null check (total > 0),
  statut text not null default 'collecte_en_attente' check (statut in (
    'collecte_en_attente', -- en attente de validation par l'expéditeur
    'collecte_echec',      -- paiement refusé / abandonné
    'transfert_en_cours',  -- fonds collectés, reversement lancé
    'reussi',
    'transfert_echec'      -- fonds collectés mais reversement échoué (à traiter)
  )),
  jeko_payment_id text unique,
  jeko_transfer_id text unique,
  erreur text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index transferts_expediteur_idx on public.transferts (expediteur, created_at desc);

alter table public.transferts enable row level security;

create policy "transferts: lecture par l'expéditeur"
  on public.transferts for select to authenticated
  using (expediteur = (select auth.uid()));

-- Passage atomique collecte réussie → reversement : un seul appel gagne
create or replace function public.claim_transfert_payout(p_id uuid)
returns boolean
language sql
security definer
set search_path = ''
as $$
  with u as (
    update public.transferts
       set statut = 'transfert_en_cours', updated_at = now()
     where id = p_id and statut = 'collecte_en_attente'
    returning 1
  )
  select exists (select 1 from u);
$$;

revoke all on function public.claim_transfert_payout(uuid) from public, anon, authenticated;
