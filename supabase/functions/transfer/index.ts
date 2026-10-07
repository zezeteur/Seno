import {
  adminClient, applyJekoStatus, corsHeaders, createPaymentRequest, getPaymentRequest, getTransfer,
  JEKO_METHODS, JekoError, json, paymentReference, setStatus,
} from '../_shared/jeko.ts';

const MIN_AMOUNT = 200;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const TRANSFERT_COLUMNS =
  'id, destinataire_label, numero_destination, reseau_destination, montant, frais, total, statut, erreur, created_at';

// Envoi d'argent : create (collecte Jèko sur le compte de l'expéditeur) → status (suivi).
// Le reversement au destinataire est lancé à la confirmation de la collecte (webhook ou suivi).
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  try {
    const admin = adminClient();
    const jwt = req.headers.get('Authorization')?.replace('Bearer ', '') ?? '';
    const { data: auth } = await admin.auth.getUser(jwt);
    if (!auth.user) return json({ error: 'unauthorized' }, 401);
    const userId = auth.user.id;

    const body = await req.json();

    if (body.action === 'create') {
      const {
        compte_id, amount, sender_pays_fees, to_compte_id, to_numero, to_reseau_id, label, idempotency_key,
        payment_request_id,
      } = body;
      if (
        typeof idempotency_key !== 'string' || !UUID_RE.test(idempotency_key) ||
        typeof compte_id !== 'string' || !Number.isInteger(amount) ||
        amount < MIN_AMOUNT || typeof label !== 'string' || !label.trim()
      ) {
        return json({ error: 'invalid_request' }, 400);
      }

      // Rejeu (double tap, renvoi après timeout) : on renvoie l'envoi déjà créé
      const findExisting = () =>
        admin.from('transferts').select('id, statut, erreur, jeko_redirect_url')
          .eq('expediteur', userId).eq('idempotency_key', idempotency_key).maybeSingle();
      const replay = (t: { id: string; statut: string; erreur: string | null; jeko_redirect_url: string | null }) =>
        t.statut === 'collecte_echec'
          ? json({ error: 'payment_failed', reason: t.erreur }, 502)
          : json({ id: t.id, redirect_url: t.jeko_redirect_url ?? '' });
      const { data: existing } = await findExisting();
      if (existing) return replay(existing);

      // Paiement d'une demande (« Encaisser ») : montant et compte crédité imposés
      if (payment_request_id !== undefined) {
        if (typeof payment_request_id !== 'string' || !UUID_RE.test(payment_request_id)) {
          return json({ error: 'invalid_request' }, 400);
        }
        const { data: pr } = await admin
          .from('payment_requests').select('payeur, compte_destination, montant')
          .eq('id', payment_request_id).maybeSingle();
        const { data: prStatut, error: prError } = await admin.rpc('payment_request_statut', {
          p_id: payment_request_id,
        });
        if (prError) throw prError;
        if (
          !pr || pr.payeur !== userId || prStatut !== 'en_attente' ||
          to_compte_id !== pr.compte_destination || amount !== pr.montant || sender_pays_fees === false
        ) {
          return json({ error: 'invalid_payment_request' }, 400);
        }
      }

      const { data: source } = await admin
        .from('comptes').select('id, numero, reseaux:id_reseau(abreviation, statut)')
        .eq('id', compte_id).eq('proprietaire', userId).maybeSingle();
      const sourceReseau = source?.reseaux as unknown as { abreviation: string; statut: boolean } | null;
      const sourceMethod = JEKO_METHODS[sourceReseau?.abreviation.toUpperCase() ?? ''];
      if (!source || !sourceReseau?.statut || !sourceMethod) return json({ error: 'invalid_request' }, 400);

      // Destination : compte Seno (id obtenu via get_seno_user_comptes), sinon numéro + réseau
      let dest: { compte: string | null; numero: string; reseau: string };
      // Destinataire marchand (boutique active) : il paie les frais
      let merchantPaysFees = false;
      if (typeof to_compte_id === 'string') {
        const { data: c } = await admin
          .from('comptes').select('id, numero, id_reseau, proprietaire').eq('id', to_compte_id).maybeSingle();
        if (!c) return json({ error: 'invalid_request' }, 400);
        dest = { compte: c.id, numero: c.numero, reseau: c.id_reseau };
        if (c.proprietaire !== userId) {
          const { data: shop, error: shopError } = await admin
            .from('merchant_requests').select('user_id')
            .eq('user_id', c.proprietaire).eq('is_active', true).maybeSingle();
          if (shopError) throw shopError;
          merchantPaysFees = shop !== null;
        }
      } else if (typeof to_numero === 'string' && /^\d{10}$/.test(to_numero) && typeof to_reseau_id === 'string') {
        dest = { compte: null, numero: to_numero, reseau: to_reseau_id };
      } else {
        return json({ error: 'invalid_request' }, 400);
      }
      if (dest.compte === source.id) return json({ error: 'invalid_request' }, 400);
      const { data: destReseau } = await admin
        .from('reseaux').select('abreviation').eq('id', dest.reseau).eq('statut', true).maybeSingle();
      if (!destReseau || !JEKO_METHODS[destReseau.abreviation.toUpperCase()]) {
        return json({ error: 'invalid_request' }, 400);
      }

      // Liste noire du back-office : envoi interdit depuis / vers ce numéro
      const { data: bloque, error: bloqueError } = await admin.rpc('numero_bloque', {
        p_source: source.numero, p_destination: dest.numero,
      });
      if (bloqueError) throw bloqueError;
      if (bloque) {
        const { error: flagError } = await admin.rpc('fraud_flag', {
          p_user: userId,
          p_regle: 'liste_noire',
          p_message: bloque === 'source'
            ? `Tentative d'envoi depuis un numéro bloqué (${source.numero})`
            : `Tentative d'envoi vers un numéro bloqué (${dest.numero})`,
          p_details: { numero: bloque === 'source' ? source.numero : dest.numero, sens: bloque },
        });
        if (flagError) console.error('fraud_flag', flagError);
        return json({ error: 'number_blocked' }, 403);
      }

      // Frais recalculés côté serveur (même formule que l'app)
      const { data: frais, error: feeError } = await admin
        .from('frais_transfert').select('pourcentage').eq('id', 1).single();
      if (feeError) throw feeError;
      const fee = Math.ceil((amount * Number(frais.pourcentage)) / 100);
      // Marchand : frais retirés du montant reçu, quel que soit le choix de l'app
      const senderPays = !merchantPaysFees && sender_pays_fees !== false;
      const montant = senderPays ? amount : amount - fee;
      const total = senderPays ? amount + fee : amount;
      if (montant < 5) return json({ error: 'invalid_request' }, 400);

      // Plafonds (identiques pour tous, sur le montant reçu) vérifiés et envoi créé
      // dans la même transaction, sous verrou par expéditeur
      const { data: created, error } = await admin.rpc('insert_transfert_plafonne', {
        p_expediteur: userId,
        p_compte_source: source.id,
        p_numero_source: source.numero,
        p_compte_destination: dest.compte,
        p_destinataire_label: label.trim().slice(0, 100),
        p_numero_destination: dest.numero,
        p_reseau_destination: dest.reseau,
        p_montant: montant,
        p_frais: fee,
        p_total: total,
        p_idempotency_key: idempotency_key,
      });
      if (error) {
        // Requête concurrente avec la même clé : elle a gagné l'insertion
        if (error.code === '23505') {
          const { data: winner } = await findExisting();
          if (winner) return replay(winner);
        }
        throw error;
      }
      if (created.error) return json({ error: created.error, limit: created.limit }, 400);
      const row = { id: created.id as string };
      if (payment_request_id !== undefined) {
        const { error: linkError } = await admin
          .from('payment_requests').update({ transfert_id: row.id, updated_at: new Date().toISOString() })
          .eq('id', payment_request_id);
        if (linkError) console.error('payment request link', linkError);
      }

      try {
        const payment = await createPaymentRequest({
          transfertId: row.id,
          amount: total,
          reference: paymentReference(row.id),
          method: sourceMethod,
          numero: source.numero,
        });
        await setStatus(admin, row.id, {
          jeko_payment_id: payment.id,
          // Wave / Orange : page de validation à rouvrir depuis l'historique
          // (MTN / Moov valident par USSD : pas de page)
          jeko_redirect_url: ['wave', 'orange'].includes(sourceMethod) ? payment.redirectUrl : null,
        });
        if (payment.status !== 'pending') {
          await applyJekoStatus(admin, { kind: 'p', id: row.id }, payment.status, payment.errorReason);
        }
        return json({ id: row.id, redirect_url: payment.redirectUrl });
      } catch (e) {
        // Code Jèko pour l'app ; le détail interne (missing_env_…, invalid_env_…) reste dans les logs
        const reason = e instanceof JekoError ? e.code : 'payment_unavailable';
        console.error('jeko payment request', e);
        await setStatus(admin, row.id, { statut: 'collecte_echec', erreur: reason });
        return json({ error: 'payment_failed', reason }, 502);
      }
    }

    if (body.action === 'status') {
      if (typeof body.id !== 'string') return json({ error: 'invalid_request' }, 400);
      const read = () =>
        admin.from('transferts')
          .select(`${TRANSFERT_COLUMNS}, jeko_payment_id, jeko_transfer_id, jeko_refund_id, tentatives_reversement, dest:compte_destination(proprietaire)`)
          .eq('id', body.id).eq('expediteur', userId).maybeSingle();
      let { data: t } = await read();
      if (!t) return json({ error: 'not_found' }, 404);

      // Suivi actif si le webhook n'est pas encore arrivé
      try {
        if (t.statut === 'collecte_en_attente' && t.jeko_payment_id) {
          const p = await getPaymentRequest(t.jeko_payment_id);
          await applyJekoStatus(admin, { kind: 'p', id: t.id }, p.status, p.errorReason);
        } else if (t.statut === 'transfert_en_cours' && t.jeko_transfer_id) {
          const tr = await getTransfer(t.jeko_transfer_id);
          await applyJekoStatus(
            admin, { kind: 't', id: t.id, attempt: t.tentatives_reversement || undefined }, tr.status,
          );
        } else if (t.statut === 'rembourse_en_cours' && t.jeko_refund_id) {
          const r = await getTransfer(t.jeko_refund_id);
          await applyJekoStatus(admin, { kind: 'r', id: t.id }, r.status);
        }
        ({ data: t } = await read());
      } catch (e) {
        console.error('jeko status poll', e);
      }
      const {
        jeko_payment_id: _p, jeko_transfer_id: _t, jeko_refund_id: _r, tentatives_reversement: _n, dest, ...publicRow
      } = t!;
      // Compte Seno d'un autre utilisateur : numéro masqué (07 •• •• 45 67), comme l'historique
      const owner = (dest as unknown as { proprietaire: string } | null)?.proprietaire;
      if (owner && owner !== userId) {
        const n = publicRow.numero_destination;
        publicRow.numero_destination = `${n.slice(0, 2)} •• •• ${n.slice(6, 8)} ${n.slice(8, 10)}`;
      }
      return json(publicRow);
    }

    return json({ error: 'invalid_request' }, 400);
  } catch (e) {
    console.error(e);
    return json({ error: 'server_error' }, 500);
  }
});
