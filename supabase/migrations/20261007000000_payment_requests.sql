-- Demandes de paiement (« Encaisser ») : un utilisateur demande un montant à un
-- autre compte Seno, crédité sur l'un de ses comptes. Le payeur accepte (envoi
-- classique via l'Edge Function transfer, lié par payment_request_id) ou refuse.
-- Création : Edge Function payment-request (push au payeur). Pas d'écriture
-- directe depuis l'app : lecture via RLS, réponses via RPC.

create table if not exists public.payment_requests (
  id uuid primary key default gen_random_uuid(),
  demandeur uuid not null references auth.users (id) on delete cascade,
  payeur uuid not null references auth.users (id) on delete cascade,
  compte_destination uuid not null references public.comptes (id) on delete cascade,
  montant integer not null check (montant between 200 and 1000000),
  statut text not null default 'en_attente'
    check (statut in ('en_attente', 'refusee', 'annulee')),
  -- Dernier envoi lancé par le payeur pour cette demande
  transfert_id uuid references public.transferts (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  check (demandeur <> payeur)
);
create index if not exists payment_requests_payeur_idx
  on public.payment_requests (payeur, created_at desc);
create index if not exists payment_requests_demandeur_idx
  on public.payment_requests (demandeur, created_at desc);

alter table public.payment_requests enable row level security;
drop policy if exists "payment_requests_parties" on public.payment_requests;
create policy "payment_requests_parties" on public.payment_requests
  for select to authenticated
  using ((select auth.uid()) in (demandeur, payeur));

-- Statut affiché : payée si l'envoi lié a abouti (ou est en cours de reversement),
-- expirée après 7 jours, sinon le statut stocké
create or replace function public.payment_request_statut(p_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when t.statut in ('reussi', 'transfert_en_cours', 'reversement_relance') then 'payee'
    when t.statut = 'collecte_en_attente' then 'en_paiement'
    when r.statut = 'en_attente' and r.expires_at < now() then 'expiree'
    else r.statut
  end
  from public.payment_requests r
  left join public.transferts t on t.id = r.transfert_id
  where r.id = p_id;
$$;
revoke all on function public.payment_request_statut(uuid) from public, anon, authenticated;
grant execute on function public.payment_request_statut(uuid) to service_role;

-- Demandes reçues (à payer) et envoyées, les plus récentes d'abord
create or replace function public.get_my_payment_requests()
returns table (
  id uuid, sens text, pseudo text, avatar_url text, montant integer,
  compte_destination uuid, statut text, created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  return query
    select r.id,
           case when r.payeur = v_uid then 'recue' else 'envoyee' end,
           p.pseudo,
           p.avatar_url,
           r.montant,
           -- Le payeur en a besoin pour l'envoi ; inutile au demandeur
           case when r.payeur = v_uid then r.compte_destination end,
           public.payment_request_statut(r.id),
           r.created_at
    from public.payment_requests r
    join public.profiles p
      on p.id = case when r.payeur = v_uid then r.demandeur else r.payeur end
    where v_uid in (r.demandeur, r.payeur)
      and r.created_at > now() - interval '30 days'
    order by r.created_at desc
    limit 50;
end;
$$;
revoke all on function public.get_my_payment_requests() from public, anon;
grant execute on function public.get_my_payment_requests() to authenticated;

-- Le payeur refuse, le demandeur annule (seulement tant qu'elle est en attente)
create or replace function public.respond_payment_request(p_id uuid, p_action text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_req public.payment_requests;
begin
  if v_uid is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  select * into v_req from public.payment_requests where id = p_id for update;
  if not found
     or p_action not in ('refuser', 'annuler')
     or (p_action = 'refuser' and v_req.payeur <> v_uid)
     or (p_action = 'annuler' and v_req.demandeur <> v_uid) then
    raise exception 'not_found' using errcode = 'P0002';
  end if;
  if public.payment_request_statut(p_id) <> 'en_attente' then
    raise exception 'not_pending' using errcode = 'P0001';
  end if;
  update public.payment_requests
     set statut = case p_action when 'refuser' then 'refusee' else 'annulee' end,
         updated_at = now()
   where id = p_id;
end;
$$;
revoke all on function public.respond_payment_request(uuid, text) from public, anon;
grant execute on function public.respond_payment_request(uuid, text) to authenticated;
