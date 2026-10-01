import {
  adminClient, applyJekoStatus, corsHeaders, createPaymentRequest, getPaymentRequest, getTransfer,
  JEKO_METHODS, JekoError, json, paymentReference, setStatus,
} from '../_shared/jeko.ts';

const MIN_AMOUNT = 200;
const MAX_AMOUNT = 1_000_000;
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
      } = body;
      if (
        typeof idempotency_key !== 'string' || !UUID_RE.test(idempotency_key) ||
        typeof compte_id !== 'string' || !Number.isInteger(amount) ||
        amount < MIN_AMOUNT || amount > MAX_AMOUNT || typeof label !== 'string' || !label.trim()
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

      const { data: source } = await admin
        .from('comptes').select('id, numero, reseaux:id_reseau(abreviation, statut)')
        .eq('id', compte_id).eq('proprietaire', userId).maybeSingle();
      const sourceReseau = source?.reseaux as unknown as { abreviation: string; statut: boolean } | null;
      const sourceMethod = JEKO_METHODS[sourceReseau?.abreviation.toUpperCase() ?? ''];
      if (!source || !sourceReseau?.statut || !sourceMethod) return json({ error: 'invalid_request' }, 400);

      // Destination : compte Seno (id obtenu via get_seno_user_comptes), sinon numéro + réseau
      let dest: { compte: string | null; numero: string; reseau: string };
      if (typeof to_compte_id === 'string') {
        const { data: c } = await admin
          .from('comptes').select('id, numero, id_reseau').eq('id', to_compte_id).maybeSingle();
        if (!c) return json({ error: 'invalid_request' }, 400);
        dest = { compte: c.id, numero: c.numero, reseau: c.id_reseau };
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

      // Frais recalculés côté serveur (même formule que l'app)
      const { data: frais, error: feeError } = await admin
        .from('frais_transfert').select('pourcentage').eq('id', 1).single();
      if (feeError) throw feeError;
      const fee = Math.ceil((amount * Number(frais.pourcentage)) / 100);
      const montant = sender_pays_fees === false ? amount - fee : amount;
      const total = sender_pays_fees === false ? amount : amount + fee;
      if (montant < 5) return json({ error: 'invalid_request' }, 400);

      const { data: row, error } = await admin.from('transferts').insert({
        expediteur: userId,
        compte_source: source.id,
        numero_source: source.numero,
        compte_destination: dest.compte,
        destinataire_label: label.trim().slice(0, 100),
        numero_destination: dest.numero,
        reseau_destination: dest.reseau,
        montant,
        frais: fee,
        total,
        idempotency_key,
      }).select('id').single();
      if (error) {
        // Requête concurrente avec la même clé : elle a gagné l'insertion
        if (error.code === '23505') {
          const { data: winner } = await findExisting();
          if (winner) return replay(winner);
        }
        throw error;
      }

      try {
        const payment = await createPaymentRequest({
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
        // Code Jèko, ou secret manquant / mal formé (missing_env_…, invalid_env_…)
        const reason = e instanceof JekoError ? e.code : (e as Error).message;
        console.error('jeko payment request', e);
        await setStatus(admin, row.id, { statut: 'collecte_echec', erreur: reason });
        return json({ error: 'payment_failed', reason }, 502);
      }
    }

    if (body.action === 'status') {
      if (typeof body.id !== 'string') return json({ error: 'invalid_request' }, 400);
      const read = () =>
        admin.from('transferts')
          .select(`${TRANSFERT_COLUMNS}, jeko_payment_id, jeko_transfer_id`)
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
          await applyJekoStatus(admin, { kind: 't', id: t.id }, tr.status);
        }
        ({ data: t } = await read());
      } catch (e) {
        console.error('jeko status poll', e);
      }
      const { jeko_payment_id: _p, jeko_transfer_id: _t, ...publicRow } = t!;
      return json(publicRow);
    }

    return json({ error: 'invalid_request' }, 400);
  } catch (e) {
    console.error(e);
    return json({ error: 'server_error' }, 500);
  }
});
