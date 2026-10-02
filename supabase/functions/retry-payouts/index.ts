import { adminClient, json, launchPayout } from '../_shared/jeko.ts';

// Relance des reversements refusés par Jèko, appelée chaque minute par pg_cron.
// Déployé sans vérification JWT : authentifié par `x-cron-secret` (secret `cron_secret` du Vault).
Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
  const secret = req.headers.get('x-cron-secret') ?? '';

  try {
    const admin = adminClient();
    const { data: ok, error: authError } = await admin.rpc('check_cron_secret', { p_secret: secret });
    if (authError) throw authError;
    if (!secret || !ok) return json({ error: 'unauthorized' }, 401);
    const { data: ids, error } = await admin.rpc('claim_reversements_relance', { p_limit: 20 });
    if (error) throw error;
    for (const id of (ids ?? []) as string[]) {
      try {
        await launchPayout(admin, id);
      } catch (e) {
        // Lecture / écriture en base échouée : envoi resté `transfert_en_cours`, visible pour le support
        console.error('retry payout', id, e);
      }
    }
    return json({ ok: true, count: ids?.length ?? 0 });
  } catch (e) {
    console.error(e);
    return json({ error: 'server_error' }, 500);
  }
});
