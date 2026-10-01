-- Temps réel : chaque création / changement de statut d'un envoi est diffusé
-- sur le canal privé « transactions:<user_id> » de l'expéditeur et du destinataire.
-- Message minimal (id + statut) : l'app recharge ensuite get_my_transactions.
create or replace function public.broadcast_transfert_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payload jsonb := jsonb_build_object('id', new.id, 'statut', new.statut);
  v_destinataire uuid;
begin
  perform realtime.send(v_payload, 'transfert', 'transactions:' || new.expediteur, true);

  -- Destinataire Seno : prévenu seulement quand l'argent est arrivé
  if new.statut = 'reussi' and new.compte_destination is not null then
    select c.proprietaire into v_destinataire
    from public.comptes c where c.id = new.compte_destination;
    if v_destinataire is not null and v_destinataire <> new.expediteur then
      perform realtime.send(v_payload, 'transfert', 'transactions:' || v_destinataire, true);
    end if;
  end if;
  return null;
end;
$$;

revoke all on function public.broadcast_transfert_change() from public, anon, authenticated;

create trigger transferts_broadcast
  after insert or update of statut on public.transferts
  for each row execute function public.broadcast_transfert_change();

-- Chacun ne peut écouter que son propre canal
create policy "transactions: écoute de son canal"
  on realtime.messages for select to authenticated
  using (
    realtime.topic() = 'transactions:' || (select auth.uid())::text
    and realtime.messages.extension = 'broadcast'
  );
