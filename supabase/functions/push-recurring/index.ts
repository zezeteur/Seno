import { adminClient, json } from '../_shared/jeko.ts';
import { sendPush } from '../_shared/fcm.ts';

// Notifications push récurrentes programmées depuis le back-office (table push_schedules).
// Appelée par pg_cron (`push-recurring`, toutes les 5 min).
// Déployée sans vérification JWT : authentifiée par `x-cron-secret` (secret `cron_secret` du Vault).

type Schedule = {
  id: string; admin_id: string; categorie: string; segment: string; segment_param: string | null;
  jours: number; titre: string; message: string;
};

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
  const secret = req.headers.get('x-cron-secret') ?? '';

  try {
    const db = adminClient();
    const { data: ok, error: authError } = await db.rpc('check_cron_secret', { p_secret: secret });
    if (authError) throw authError;
    if (!secret || !ok) return json({ error: 'unauthorized' }, 401);

    // next_run est déjà avancé : un échec n'entraîne pas de renvoi en boucle
    const { data: due, error } = await db.rpc('push_claim_due');
    if (error) throw error;

    const results = [];
    for (const s of (due ?? []) as Schedule[]) {
      try {
        const { data: rows, error: audErr } = await db.rpc('push_audience', {
          p_segment: s.segment, p_param: s.segment_param, p_categorie: s.categorie, p_days: s.jours,
        });
        if (audErr) throw audErr;
        const list = (rows ?? []) as { token: string; user_id: string }[];
        const tokens = list.map((r) => r.token);
        const { sent, failed } = tokens.length
          ? await sendPush(db, tokens, { title: s.titre, body: s.message, categorie: s.categorie })
          : { sent: 0, failed: 0 };

        await db.from('push_campaigns').insert({
          admin_id: s.admin_id,
          schedule_id: s.id,
          categorie: s.categorie,
          segment: s.segment === 'inactive' ? `inactive_${s.jours}j` : s.segment,
          segment_param: s.segment_param,
          titre: s.titre,
          message: s.message,
          destinataires: new Set(list.map((r) => r.user_id)).size,
          envoyes: sent,
          echecs: failed,
        });
        results.push({ id: s.id, sent, failed });
      } catch (e) {
        console.error('push-recurring', s.id, e);
        results.push({ id: s.id, error: String(e) });
      }
    }
    return json({ processed: results.length, results });
  } catch (e) {
    console.error('push-recurring', e);
    return json({ error: 'internal_error' }, 500);
  }
});
