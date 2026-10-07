-- Temps réel : création / changement d'une demande de paiement diffusé sur le
-- canal privé « transactions:<user_id> » du demandeur et du payeur (déjà écouté
-- par l'app). Message minimal : l'app recharge get_my_payment_requests.
create or replace function public.broadcast_payment_request_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payload jsonb := jsonb_build_object('id', new.id);
begin
  perform realtime.send(v_payload, 'payment_request', 'transactions:' || new.payeur, true);
  perform realtime.send(v_payload, 'payment_request', 'transactions:' || new.demandeur, true);
  return null;
end;
$$;

revoke all on function public.broadcast_payment_request_change() from public, anon, authenticated;

drop trigger if exists payment_requests_broadcast on public.payment_requests;
create trigger payment_requests_broadcast
  after insert or update on public.payment_requests
  for each row execute function public.broadcast_payment_request_change();
