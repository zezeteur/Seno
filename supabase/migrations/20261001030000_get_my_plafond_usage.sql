-- Montants déjà envoyés par l'utilisateur connecté, comptés comme dans
-- insert_transfert_plafonne : montant reçu, envois échoués exclus, UTC.
create or replace function public.get_my_plafond_usage()
returns table (journalier bigint, mensuel bigint)
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(sum(montant) filter (
           where created_at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC'), 0),
         coalesce(sum(montant), 0)
    from public.transferts
   where expediteur = (select auth.uid())
     and statut <> 'collecte_echec'
     and created_at >= date_trunc('month', now() at time zone 'UTC') at time zone 'UTC';
$$;

revoke all on function public.get_my_plafond_usage() from public, anon;
grant execute on function public.get_my_plafond_usage() to authenticated;
