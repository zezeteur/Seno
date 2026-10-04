import { adminClient, getStoreBalance, json } from '../_shared/jeko.ts';
import { esc, fcfa, layout, sendEmail, validRecipients } from '../_shared/mail.ts';

// Rapport quotidien et alertes du back-office, envoyés par email (Resend).
// Appelée par pg_cron (`admin-alerts` toutes les 5 min, `admin-daily-report` à 8 h)
// ou par le back-office (bouton « Envoyer un test »).
// Déployée sans vérification JWT : authentifiée par `x-cron-secret` (secret `cron_secret` du Vault).

type Mode = 'alerts' | 'daily' | 'test';

const row = (label: string, value: string, color = '#18181b') =>
  `<tr><td style="padding:6px 0;color:#71717a">${esc(label)}</td><td style="padding:6px 0;text-align:right;font-weight:bold;color:${color}">${esc(value)}</td></tr>`;

type Report = {
  jour: string; transferts: number; reussis: number; volume: number; frais: number;
  paiements_abandonnes: number; rembourses: number; incidents_ouverts: number;
  inscrits: number; nouvelles_boutiques: number;
  reseaux: { nom: string; total: number; reussis: number; volume: number }[];
};

function dailyEmail(r: Report): { subject: string; html: string } {
  const jour = new Date(`${r.jour}T00:00:00Z`).toLocaleDateString('fr-FR', {
    weekday: 'long', day: 'numeric', month: 'long', timeZone: 'UTC',
  });
  const taux = r.transferts ? Math.round((r.reussis / r.transferts) * 100) : 0;
  const reseaux = r.reseaux.length
    ? `<h2 style="font-size:15px;margin:24px 0 8px">Par réseau</h2>
       <table style="width:100%;border-collapse:collapse;font-size:14px">
         <tr style="color:#71717a;text-align:left"><th>Réseau</th><th style="text-align:right">Transferts</th><th style="text-align:right">Réussite</th><th style="text-align:right">Volume</th></tr>
         ${r.reseaux.map((n) => `<tr style="border-top:1px solid #e4e4e7"><td style="padding:6px 0">${esc(n.nom)}</td><td style="text-align:right">${n.total}</td><td style="text-align:right">${n.total ? Math.round((n.reussis / n.total) * 100) : 0} %</td><td style="text-align:right">${esc(fcfa(n.volume))}</td></tr>`).join('')}
       </table>`
    : '';
  const html = layout(`Rapport du ${jour}`, `
    <table style="width:100%;border-collapse:collapse;font-size:14px">
      ${row('Volume réussi', fcfa(r.volume))}
      ${row('Frais encaissés', fcfa(r.frais))}
      ${row('Transferts', `${r.transferts} (${taux} % réussis)`)}
      ${row('Paiements abandonnés', String(r.paiements_abandonnes))}
      ${row('Remboursements', String(r.rembourses))}
      ${row('Nouveaux inscrits', String(r.inscrits))}
      ${row('Incidents à traiter (en cours)', String(r.incidents_ouverts), r.incidents_ouverts ? '#dc2626' : '#16a34a')}
      ${row('Nouvelles boutiques', String(r.nouvelles_boutiques ?? 0))}
    </table>${reseaux}`);
  return { subject: `Seno · Rapport du ${jour} · ${fcfa(r.volume)}`, html };
}

/** Relève le solde Jèko (historique 30 jours) : l'alerte « solde bas » est calculée par admin_alert_conditions. */
async function recordBalance(admin: ReturnType<typeof adminClient>) {
  const row = await getStoreBalance()
    .then((montant) => ({ montant, erreur: null }))
    .catch((e) => ({ montant: null, erreur: String(e?.message ?? e).slice(0, 200) }));
  const { error } = await admin.from('jeko_soldes').insert(row);
  if (error) throw error;
  await admin.from('jeko_soldes').delete().lt('created_at', new Date(Date.now() - 30 * 86_400_000).toISOString());
  return row.montant;
}

/** Compare les conditions courantes aux alertes ouvertes : envoie les nouvelles et les résolues. */
async function runAlerts(admin: ReturnType<typeof adminClient>, to: string[]) {
  const [{ data: current, error: e1 }, { data: open, error: e2 }] = await Promise.all([
    admin.rpc('admin_alert_conditions'),
    admin.from('admin_alerts').select('key, message, opened_at').is('resolved_at', null),
  ]);
  if (e1) throw e1;
  if (e2) throw e2;

  const now = new Date().toISOString();
  const cur = new Map((current ?? []).map((c: { key: string; message: string }) => [c.key, c.message]));
  const openKeys = new Set((open ?? []).map((o) => o.key));
  const nouvelles = [...cur].filter(([k]) => !openKeys.has(k));
  const resolues = (open ?? []).filter((o) => !cur.has(o.key));

  if (cur.size) {
    const { error } = await admin.from('admin_alerts').upsert(
      [...cur].map(([key, message]) => ({
        key, message, last_seen_at: now,
        ...(openKeys.has(key) ? {} : { opened_at: now, resolved_at: null }),
      })),
    );
    if (error) throw error;
  }
  if (resolues.length) {
    const { error } = await admin.from('admin_alerts')
      .update({ resolved_at: now }).in('key', resolues.map((r) => r.key));
    if (error) throw error;
  }

  if (nouvelles.length) {
    await sendEmail(
      to,
      `⚠️ Seno · ${nouvelles.length === 1 ? nouvelles[0][1] : `${nouvelles.length} alertes`}`,
      layout('Nouvelle(s) alerte(s)', `<ul style="padding-left:18px;font-size:14px;line-height:1.6">
        ${nouvelles.map(([, m]) => `<li style="color:#dc2626">${esc(m)}</li>`).join('')}</ul>
        ${cur.size > nouvelles.length ? `<p style="font-size:13px;color:#71717a">${cur.size - nouvelles.length} autre(s) alerte(s) toujours en cours.</p>` : ''}`),
    );
  }
  if (resolues.length) {
    await sendEmail(
      to,
      `✅ Seno · ${resolues.length === 1 ? 'Alerte résolue' : `${resolues.length} alertes résolues`}`,
      layout('Alerte(s) résolue(s)', `<ul style="padding-left:18px;font-size:14px;line-height:1.6">
        ${resolues.map((r) => `<li style="color:#16a34a">${esc(r.message)}</li>`).join('')}</ul>`),
    );
  }
  return { ouvertes: cur.size, nouvelles: nouvelles.length, resolues: resolues.length };
}

const REGLES: Record<string, string> = {
  rafale: 'Envois en rafale',
  nouveau_plafond: 'Nouveau compte proche des plafonds',
  appareil_partage: 'Plusieurs comptes sur un appareil',
  echecs_code: 'Échecs de code d’accès',
  destinataires: 'Nombreux destinataires',
  expediteurs: 'Nombreux expéditeurs',
  liste_noire: 'Numéro sur liste noire',
};

/** Détection d'activité suspecte : analyse, puis email récapitulatif des détections pas encore signalées. */
async function runFraud(admin: ReturnType<typeof adminClient>, to: string[]) {
  const { error } = await admin.rpc('admin_fraud_scan');
  if (error) throw error;
  const [{ data: flags, error: e1 }, { data: settings, error: e2 }] = await Promise.all([
    admin.from('fraud_flags').select('id, user_id, regle, message').eq('notifie', false).order('created_at').limit(200),
    admin.from('fraud_settings').select('alertes_email').eq('id', 1).single(),
  ]);
  if (e1) throw e1;
  if (e2) throw e2;
  if (!flags?.length) return { detections: 0 };

  if (settings.alertes_email) {
    const ids = [...new Set(flags.map((f) => f.user_id))];
    const { data: profiles } = await admin.from('profiles').select('id, pseudo, phone').in('id', ids);
    const who = new Map((profiles ?? []).map((p) => [p.id, p.pseudo ? `@${p.pseudo}` : p.phone || p.id.slice(0, 8)]));
    const base = Deno.env.get('BACKOFFICE_URL')?.replace(/\/+$/, '');
    await sendEmail(
      to,
      `🚨 Seno · ${flags.length === 1 ? REGLES[flags[0].regle] ?? 'Activité suspecte' : `${flags.length} activités suspectes`}`,
      layout('Activité suspecte détectée', `<ul style="padding-left:18px;font-size:14px;line-height:1.6">
        ${flags.map((f) => {
          const name = esc(who.get(f.user_id) ?? f.user_id);
          const link = base ? `<a href="${esc(`${base}/utilisateurs/${f.user_id}`)}">${name}</a>` : name;
          return `<li><b>${esc(REGLES[f.regle] ?? f.regle)}</b> · ${link}<br><span style="color:#71717a">${esc(f.message)}</span></li>`;
        }).join('')}</ul>
        <p style="font-size:13px;color:#71717a">Ces comptes figurent dans « Comptes à surveiller ».</p>`, '/fraude'),
    );
  }
  const { error: e3 } = await admin.from('fraud_flags').update({ notifie: true }).in('id', flags.map((f) => f.id));
  if (e3) throw e3;
  return { detections: flags.length };
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
  const secret = req.headers.get('x-cron-secret') ?? '';

  try {
    const admin = adminClient();
    const { data: ok, error: authError } = await admin.rpc('check_cron_secret', { p_secret: secret });
    if (authError) throw authError;
    if (!secret || !ok) return json({ error: 'unauthorized' }, 401);

    const body = await req.json().catch(() => ({}));
    const mode: Mode = ['alerts', 'daily', 'test'].includes(body?.mode) ? body.mode : 'alerts';

    const { data: settings, error } = await admin
      .from('report_settings').select('*').eq('id', 1).single();
    if (error) throw error;
    const to = validRecipients(settings.recipients as string[]);
    if (!to.length) return json({ ok: true, skipped: 'no_recipients' });

    if (mode === 'alerts') {
      const fraude = await runFraud(admin, to).catch((e) => {
        console.error('fraud scan', e);
        return { detections: -1 };
      });
      const solde = await recordBalance(admin).catch((e) => {
        console.error('jeko balance', e);
        return null;
      });
      if (!settings.alerts_enabled) return json({ ok: true, skipped: 'disabled', fraude, solde });
      return json({ ok: true, ...(await runAlerts(admin, to)), fraude, solde });
    }

    const { data: report, error: e } = await admin.rpc('admin_daily_report');
    if (e) throw e;
    if (mode === 'daily' && !settings.daily_enabled) return json({ ok: true, skipped: 'disabled' });
    const { subject, html } = dailyEmail(report as Report);
    await sendEmail(to, mode === 'test' ? `[TEST] ${subject}` : subject, html);
    return json({ ok: true, sent: to.length });
  } catch (e) {
    console.error('admin-reports', e);
    return json({ error: 'server_error' }, 500);
  }
});
