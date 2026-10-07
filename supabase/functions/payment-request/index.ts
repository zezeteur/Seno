import { adminClient, corsHeaders, json } from '../_shared/jeko.ts';
import { sendPush } from '../_shared/fcm.ts';

const MIN_AMOUNT = 200;
const MAX_AMOUNT = 1000000;
// Anti-spam : demandes en attente par demandeur
const MAX_PENDING = 20;

// Demande de paiement (« Encaisser ») : create → notifie le payeur (push).
// Réponses (refuser / annuler) et lecture : RPC respond_payment_request / get_my_payment_requests.
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
    if (body.action !== 'create') return json({ error: 'invalid_request' }, 400);

    const { payer_pseudo, compte_id, amount } = body;
    if (
      typeof payer_pseudo !== 'string' || typeof compte_id !== 'string' ||
      !Number.isInteger(amount) || amount < MIN_AMOUNT || amount > MAX_AMOUNT
    ) {
      return json({ error: 'invalid_request' }, 400);
    }

    // Compte crédité : un compte du demandeur
    const { data: compte } = await admin
      .from('comptes').select('id').eq('id', compte_id).eq('proprietaire', userId).maybeSingle();
    if (!compte) return json({ error: 'invalid_request' }, 400);

    // Pseudo exact (insensible à la casse) : on échappe les jokers de ilike
    const pseudo = payer_pseudo.replace('@', '').trim().replace(/[\\%_]/g, '\\$&');
    const { data: payer } = await admin
      .from('profiles').select('id, notif_prefs').ilike('pseudo', pseudo).maybeSingle();
    if (!payer || payer.id === userId) return json({ error: 'invalid_recipient' }, 400);

    const { count, error: countError } = await admin
      .from('payment_requests').select('id', { count: 'exact', head: true })
      .eq('demandeur', userId).eq('statut', 'en_attente').is('transfert_id', null)
      .gt('expires_at', new Date().toISOString());
    if (countError) throw countError;
    if ((count ?? 0) >= MAX_PENDING) return json({ error: 'too_many_requests' }, 429);

    const { data: row, error } = await admin.from('payment_requests').insert({
      demandeur: userId,
      payeur: payer.id,
      compte_destination: compte.id,
      montant: amount,
    }).select('id').single();
    if (error) throw error;

    // Push au payeur (si ses notifications de transactions sont actives)
    const prefs = (payer.notif_prefs ?? {}) as Record<string, boolean>;
    if (prefs.push !== false && prefs.transactions !== false) {
      try {
        const [{ data: me }, { data: tokens }] = await Promise.all([
          admin.from('profiles').select('pseudo').eq('id', userId).maybeSingle(),
          admin.from('push_tokens').select('token').eq('user_id', payer.id),
        ]);
        if (tokens?.length) {
          const formatted = amount.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
          await sendPush(admin, tokens.map((t) => t.token), {
            title: 'Demande de paiement',
            body: `@${me?.pseudo ?? 'Seno'} vous demande ${formatted} FCFA`,
            categorie: 'payment_request',
          });
        }
      } catch (e) {
        // La demande reste visible dans l'app même sans push
        console.error('payment request push', e);
      }
    }

    return json({ id: row.id });
  } catch (e) {
    console.error(e);
    return json({ error: 'server_error' }, 500);
  }
});
