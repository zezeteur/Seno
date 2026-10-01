-- Vérification des plafonds et création de l'envoi en une seule transaction.
-- Verrou par expéditeur : deux envois simultanés sont traités l'un après
-- l'autre, le second voit le cumul du premier.
-- Retour : {"id": ...} ou {"error": "limit_exceeded", "limit": "transaction" | "daily" | "monthly"}
create or replace function public.insert_transfert_plafonne(
  p_expediteur uuid,
  p_compte_source uuid,
  p_numero_source text,
  p_compte_destination uuid,
  p_destinataire_label text,
  p_numero_destination text,
  p_reseau_destination uuid,
  p_montant integer,
  p_frais integer,
  p_total integer,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_plafonds public.plafonds_transfert;
  -- Jour et mois en UTC (heure d'Abidjan)
  v_jour timestamptz := date_trunc('day', now() at time zone 'UTC') at time zone 'UTC';
  v_mois timestamptz := date_trunc('month', now() at time zone 'UTC') at time zone 'UTC';
  v_journalier bigint;
  v_mensuel bigint;
  v_id uuid;
begin
  perform pg_advisory_xact_lock(hashtextextended('plafond:' || p_expediteur::text, 0));

  select * into strict v_plafonds from public.plafonds_transfert where id = 1;
  if p_montant > v_plafonds.par_transaction then
    return jsonb_build_object('error', 'limit_exceeded', 'limit', 'transaction');
  end if;

  select coalesce(sum(montant) filter (where created_at >= v_jour), 0),
         coalesce(sum(montant), 0)
    into v_journalier, v_mensuel
    from public.transferts
   where expediteur = p_expediteur
     and statut <> 'collecte_echec'
     and created_at >= v_mois;

  if v_journalier + p_montant > v_plafonds.journalier then
    return jsonb_build_object('error', 'limit_exceeded', 'limit', 'daily');
  end if;
  if v_mensuel + p_montant > v_plafonds.mensuel then
    return jsonb_build_object('error', 'limit_exceeded', 'limit', 'monthly');
  end if;

  insert into public.transferts (
    expediteur, compte_source, numero_source, compte_destination, destinataire_label,
    numero_destination, reseau_destination, montant, frais, total, idempotency_key
  ) values (
    p_expediteur, p_compte_source, p_numero_source, p_compte_destination, p_destinataire_label,
    p_numero_destination, p_reseau_destination, p_montant, p_frais, p_total, p_idempotency_key
  )
  returning id into v_id;

  return jsonb_build_object('id', v_id);
end;
$$;

revoke all on function public.insert_transfert_plafonne(
  uuid, uuid, text, uuid, text, text, uuid, integer, integer, integer, uuid
) from public, anon, authenticated;
