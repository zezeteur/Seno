-- Statut affiché d'une demande (page de détail mise à jour en temps réel) :
-- réservé au demandeur et au payeur, null sinon
create or replace function public.get_payment_request_statut(p_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select public.payment_request_statut(r.id)
  from public.payment_requests r
  where r.id = p_id and auth.uid() in (r.demandeur, r.payeur);
$$;
revoke all on function public.get_payment_request_statut(uuid) from public, anon;
grant execute on function public.get_payment_request_statut(uuid) to authenticated;
