-- Back-office Seno v6 : les boutiques sont actives dès leur création (pas de validation).
-- Le tableau de bord compte les boutiques actives et les créations des 7 derniers jours
-- (colonne marchands_en_attente conservée pour la compatibilité, nouveau sens).
create or replace function public.admin_dashboard_stats()
returns table (
  utilisateurs bigint, utilisateurs_7j bigint, transferts_total bigint, transferts_reussis bigint,
  volume_reussi bigint, frais_encaisses bigint, volume_24h bigint, a_traiter bigint,
  marchands_en_attente bigint, marchands_actifs bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select count(*) from auth.users),
    (select count(*) from auth.users where created_at > now() - interval '7 days'),
    (select count(*) from public.transferts),
    (select count(*) from public.transferts where statut = 'reussi'),
    (select coalesce(sum(montant), 0) from public.transferts where statut = 'reussi'),
    (select coalesce(sum(frais), 0) from public.transferts where statut = 'reussi'),
    (select coalesce(sum(montant), 0) from public.transferts
      where statut = 'reussi' and created_at > now() - interval '24 hours'),
    (select count(*) from public.transferts where statut in ('transfert_echec', 'remboursement_echec')),
    (select count(*) from public.merchant_requests where created_at > now() - interval '7 days'),
    (select count(*) from public.merchant_requests where is_active);
$$;
revoke all on function public.admin_dashboard_stats() from public, anon, authenticated;
