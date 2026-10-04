import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import { adminClient, getPaymentRequest, getTransfer, json, JekoError, listTransactions, type JekoTransaction } from '../_shared/jeko.ts';
import { esc, fcfa, layout, sendEmail, validRecipients } from '../_shared/mail.ts';

// Rapprochement quotidien : pour chaque envoi Seno créé un jour donné, relit chez Jèko le paiement,
// le reversement et le remboursement enregistrés (ids stockés sur l'envoi), puis signale toute
// opération du relevé Jèko (GET /transactions) qui n'appartient à aucun envoi. Écarts dans
// `rapprochement_ecarts`. NB : dans le relevé, `reference` et `id` sont ceux de Jèko, d'où le
// passage par `transaction.id`. Email aux destinataires des rapports s'il y en a.
// Appelée par pg_cron (`jeko-reconciliation`, 6 h, jour = veille) ou par le back-office
// (`admin_run_reconciliation`, body { jour }). Authentifiée par `x-cron-secret`.

type Transfert = {
  id: string; statut: string; montant: number; total: number; created_at: string;
  jeko_payment_id: string | null; jeko_transfer_id: string | null; jeko_refund_id: string | null;
};
/** Opération Jèko d'un envoi, lue par son id (GET /payment_requests|transfers/{id}) */
type Op = {
  id: string; status: string; montant: number | null; transactionId: string | null;
  methode?: string; createdAt?: string; // transferts : rapprochés au relevé par réseau, montant et heure
};
type Ops = { p: Op | null; t: Op | null; r: Op | null };
type Ecart = {
  type: string;
  transfert_id?: string | null;
  jeko_id?: string | null;
  reference?: string | null;
  montant_seno?: number | null;
  montant_jeko?: number | null;
  statut_seno?: string | null;
  statut_jeko?: string | null;
  detail: string;
};

export const LIBELLES: Record<string, string> = {
  collecte_manquante: 'Paiement confirmé chez Seno, absent chez Jèko',
  collecte_non_traitee: 'Paiement reçu chez Jèko, envoi Seno non traité',
  reversement_manquant: 'Envoi « réussi » sans reversement chez Jèko',
  reversement_non_enregistre: 'Reversement réussi chez Jèko, envoi Seno non « réussi »',
  double_reversement: 'Destinataire payé plusieurs fois',
  remboursement_manquant: 'Envoi « remboursé » sans remboursement chez Jèko',
  remboursement_non_enregistre: 'Remboursement réussi chez Jèko, envoi Seno non « remboursé »',
  reversement_et_remboursement: 'Destinataire payé ET expéditeur remboursé',
  montant_different: 'Montant différent',
  operation_inconnue: 'Opération Jèko sans envoi Seno',
};

const NON_PAYES = ['collecte_en_attente', 'collecte_echec'];
const addDays = (d: string, n: number) => new Date(Date.parse(`${d}T00:00:00Z`) + n * 86_400_000).toISOString().slice(0, 10);

/** Écarts d'un envoi Seno au vu de ses opérations Jèko */
function compare(t: Transfert, { p, t: tr, r }: Ops): Ecart[] {
  const ecarts: Ecart[] = [];
  const base = { transfert_id: t.id, statut_seno: t.statut };
  const paye = !NON_PAYES.includes(t.statut);
  const ok = (o: Op | null) => o?.status === 'success';
  const op = (o: Op) => ({ jeko_id: o.id, montant_jeko: o.montant, statut_jeko: o.status });

  // Collecte : total payé par l'expéditeur
  if (paye && !ok(p)) {
    ecarts.push({ ...base, type: 'collecte_manquante', montant_seno: t.total, ...(p ? op(p) : {}),
      detail: p ? `Paiement Jèko « ${p.status} » alors que l’envoi est payé` : 'Aucun paiement Jèko enregistré sur l’envoi' });
  }
  if (!paye && ok(p)) {
    ecarts.push({ ...base, type: 'collecte_non_traitee', ...op(p!),
      detail: 'Argent encaissé chez Jèko mais envoi jamais lancé : rembourser ou reverser' });
  }

  // Reversement : montant reçu par le destinataire
  if (t.statut === 'reussi' && !ok(tr)) {
    ecarts.push({ ...base, type: 'reversement_manquant', montant_seno: t.montant, ...(tr ? op(tr) : {}),
      detail: tr ? `Reversement Jèko « ${tr.status} » alors que l’envoi est réussi` : 'Aucun reversement Jèko enregistré sur l’envoi' });
  }
  if (ok(tr) && t.statut !== 'reussi') {
    ecarts.push({ ...base, type: 'reversement_non_enregistre', ...op(tr!),
      detail: 'Le destinataire a été payé mais l’envoi n’est pas marqué réussi' });
  }

  // Remboursement : total rendu à l'expéditeur
  if (t.statut === 'rembourse' && !ok(r)) {
    ecarts.push({ ...base, type: 'remboursement_manquant', montant_seno: t.total, ...(r ? op(r) : {}),
      detail: r ? `Remboursement Jèko « ${r.status} » alors que l’envoi est remboursé` : 'Aucun remboursement Jèko enregistré sur l’envoi' });
  }
  if (ok(r) && t.statut !== 'rembourse') {
    ecarts.push({ ...base, type: 'remboursement_non_enregistre', ...op(r!),
      detail: 'L’expéditeur a été remboursé mais l’envoi n’est pas marqué remboursé' });
  }
  if (ok(tr) && ok(r)) {
    ecarts.push({ ...base, type: 'reversement_et_remboursement', montant_seno: t.montant + t.total,
      montant_jeko: (tr!.montant ?? 0) + (r!.montant ?? 0), statut_jeko: 'success',
      detail: 'Argent versé au destinataire ET rendu à l’expéditeur : perte pour Seno' });
  }

  // Montants (opérations réussies seulement)
  for (const [o, attendu, quoi] of [[p, t.total, 'Paiement'], [tr, t.montant, 'Reversement'], [r, t.total, 'Remboursement']] as const) {
    if (o && ok(o) && o.montant !== null && o.montant !== attendu) {
      ecarts.push({ ...base, type: 'montant_different', ...op(o), montant_seno: attendu,
        detail: `${quoi} : ${fcfa(o.montant)} chez Jèko au lieu de ${fcfa(attendu)}` });
    }
  }
  return ecarts;
}

const cents = (m?: { amount: number } | null) => (m ? Math.round(m.amount / 100) : 0);

/** Lit une opération Jèko ; 404 = inconnue chez Jèko (statut « absent ») */
async function lire(id: string | null, kind: 'p' | 'tr'): Promise<Op | null> {
  if (!id) return null;
  try {
    if (kind === 'p') {
      const x = await getPaymentRequest(id);
      // Paiement : `transaction.amount` = brut payé par l'expéditeur (le relevé, lui, est net de frais)
      return { id, status: x.status, transactionId: x.transaction?.id ?? null,
        montant: x.transaction ? cents(x.transaction.amount) : null };
    }
    const x = await getTransfer(id);
    return { id, status: x.status, transactionId: x.transaction?.id ?? null, montant: x.amount ? cents(x.amount) : null,
      methode: x.paymentMethod, createdAt: x.createdAt };
  } catch (e) {
    if (e instanceof JekoError && e.status === 404) return { id, status: 'absent', transactionId: null, montant: null };
    throw e;
  }
}

/** Exécute `fn` sur chaque élément, `n` à la fois (limite les appels simultanés à Jèko) */
async function parLots<T, R>(items: T[], n: number, fn: (x: T) => Promise<R>): Promise<R[]> {
  const out: R[] = [];
  for (let i = 0; i < items.length; i += n) out.push(...(await Promise.all(items.slice(i, i + n).map(fn))));
  return out;
}

async function reconcile(admin: SupabaseClient, jour: string) {
  const debut = `${jour}T00:00:00Z`;
  const fin = `${addDays(jour, 1)}T00:00:00Z`;
  const { error: e0 } = await admin.from('rapprochements').upsert({
    jour, statut: 'en_cours', erreur: null, started_at: new Date().toISOString(), finished_at: null,
  });
  if (e0) throw e0;

  try {
    // Relevé Jèko : la veille, le jour et le lendemain (opérations confirmées autour de minuit).
    // Envois Seno : même fenêtre, pour reconnaître toutes les opérations du jour.
    const [releve, { data: transferts, error: e1 }] = await Promise.all([
      listTransactions(addDays(jour, -1), addDays(jour, 1)),
      admin.from('transferts')
        .select('id, statut, montant, total, created_at, jeko_payment_id, jeko_transfer_id, jeko_refund_id')
        .gte('created_at', `${addDays(jour, -1)}T00:00:00Z`).lt('created_at', `${addDays(jour, 2)}T00:00:00Z`),
    ]);
    if (e1) throw e1;
    const fenetre = (transferts ?? []) as Transfert[];
    const seno = fenetre.filter((t) => t.created_at >= debut && t.created_at < fin);
    const avecJeko = fenetre.filter((t) => t.jeko_payment_id || t.jeko_transfer_id || t.jeko_refund_id);

    const ops = new Map<string, Ops>(await parLots(avecJeko, 5, async (t) =>
      [t.id, { p: await lire(t.jeko_payment_id, 'p'), t: await lire(t.jeko_transfer_id, 'tr'), r: await lire(t.jeko_refund_id, 'tr') }] as const));

    const ecarts: Ecart[] = [];
    let rapproches = 0;
    for (const t of seno) {
      const e = compare(t, ops.get(t.id) ?? { p: null, t: null, r: null });
      if (e.length) ecarts.push(...e);
      else if (!NON_PAYES.includes(t.statut)) rapproches++;
    }

    // Opérations du jour au relevé Jèko qui n'appartiennent à aucun envoi Seno
    // (ancienne tentative de reversement réussie = double paiement, retrait manuel…)
    const toutes = [...ops.values()].flatMap((o) => [o.p, o.t, o.r]).filter((o): o is Op => !!o);
    const connues = new Set(toutes.flatMap((o) => (o.transactionId ? [o.transactionId] : [])));
    // GET /transfers ne donne pas l'id de transaction : même réseau, même montant, à 5 min près
    const sorties = toutes.filter((o) => o.createdAt && !o.transactionId);
    for (const o of releve.filter((o) => o.type === 'transfer' && !connues.has(o.id))) {
      const i = sorties.findIndex((t) => t.methode === o.paymentMethod && t.montant === cents(o.amount) &&
        Math.abs(Date.parse(t.createdAt!) - Date.parse(o.createdAt)) <= 5 * 60_000);
      if (i >= 0) {
        connues.add(o.id);
        sorties.splice(i, 1);
      }
    }
    const duJour = releve.filter((o) => o.type !== 'escrow' && o.createdAt >= debut && o.createdAt < fin);
    for (const o of duJour.filter((o) => o.status !== 'error' && !connues.has(o.id))) {
      ecarts.push({ type: 'operation_inconnue', jeko_id: o.id, reference: o.reference || null,
        montant_jeko: o.type === 'payment' ? cents(o.amount) + cents(o.fees) : cents(o.amount), statut_jeko: o.status,
        detail: `${o.type === 'payment' ? 'Paiement' : 'Transfert'} ${o.paymentMethod} ${o.counterpartIdentifier || ''} sans envoi Seno`.trim() });
    }

    // Relance : les écarts déjà résolus ne sont pas recréés, les autres sont remplacés
    const { data: resolus, error: e2 } = await admin.from('rapprochement_ecarts')
      .select('type, transfert_id, jeko_id').eq('jour', jour).not('resolu_at', 'is', null);
    if (e2) throw e2;
    const cle = (e: { type: string; transfert_id?: string | null; jeko_id?: string | null }) =>
      `${e.type}|${e.transfert_id ?? ''}|${e.jeko_id ?? ''}`;
    const dejaResolus = new Set((resolus ?? []).map(cle));
    const nouveaux = ecarts.filter((e) => !dejaResolus.has(cle(e)));

    const { error: e3 } = await admin.from('rapprochement_ecarts').delete().eq('jour', jour).is('resolu_at', null);
    if (e3) throw e3;
    if (nouveaux.length) {
      const { error } = await admin.from('rapprochement_ecarts').insert(nouveaux.map((e) => ({ ...e, jour })));
      if (error) throw error;
    }

    const payes = seno.filter((t) => !NON_PAYES.includes(t.statut));
    const resume = {
      statut: nouveaux.length ? 'ecarts' : 'ok',
      transferts_seno: payes.length,
      operations_jeko: duJour.length,
      rapproches,
      ecarts: nouveaux.length,
      volume_seno: payes.reduce((s, t) => s + t.total, 0),
      volume_jeko: seno.reduce((s, t) => {
        const p = ops.get(t.id)?.p;
        return s + (p?.status === 'success' ? p.montant ?? 0 : 0);
      }, 0),
      finished_at: new Date().toISOString(),
    };
    const { error: e4 } = await admin.from('rapprochements').update(resume).eq('jour', jour);
    if (e4) throw e4;
    return { ...resume, liste: nouveaux };
  } catch (e) {
    await admin.from('rapprochements').update({
      statut: 'erreur', erreur: e instanceof Error ? e.message : String(e), finished_at: new Date().toISOString(),
    }).eq('jour', jour);
    throw e;
  }
}

function email(jour: string, r: Awaited<ReturnType<typeof reconcile>>) {
  const date = new Date(`${jour}T00:00:00Z`).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', timeZone: 'UTC' });
  const lignes = r.liste.slice(0, 30).map((e) => `<tr style="border-top:1px solid #e4e4e7">
      <td style="padding:6px 0">${esc(LIBELLES[e.type] ?? e.type)}<br><span style="color:#71717a;font-size:12px">${esc(e.detail)}</span></td>
      <td style="padding:6px 0;text-align:right;font-family:monospace;font-size:12px">${esc((e.transfert_id ?? e.jeko_id ?? '').slice(0, 8))}</td></tr>`).join('');
  return {
    subject: `⚠️ Seno · Rapprochement Jèko du ${date} : ${r.ecarts} écart(s)`,
    html: layout(`Rapprochement Jèko du ${date}`, `
      <p style="font-size:14px">${r.rapproches} envoi(s) rapproché(s) sur ${r.transferts_seno} · collectes Seno ${esc(fcfa(r.volume_seno))} / Jèko ${esc(fcfa(r.volume_jeko))}</p>
      <table style="width:100%;border-collapse:collapse;font-size:14px">${lignes}</table>
      ${r.liste.length > 30 ? `<p style="font-size:13px;color:#71717a">… et ${r.liste.length - 30} autre(s).</p>` : ''}`, `/rapprochement?jour=${jour}`),
  };
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
    const hier = addDays(new Date().toISOString().slice(0, 10), -1);
    const jour = typeof body?.jour === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(body.jour) && body.jour <= hier
      ? body.jour : hier;

    const r = await reconcile(admin, jour);
    if (r.ecarts) {
      const { data: s } = await admin.from('report_settings').select('recipients, alerts_enabled').eq('id', 1).single();
      const to = validRecipients((s?.recipients ?? []) as string[]);
      if (s?.alerts_enabled && to.length) {
        const { subject, html } = email(jour, r);
        await sendEmail(to, subject, html).catch((e) => console.error('jeko-reconciliation email', e));
      }
    }
    const { liste: _, ...resume } = r;
    return json({ ok: true, jour, ...resume });
  } catch (e) {
    console.error('jeko-reconciliation', e);
    return json({ error: 'server_error' }, 500);
  }
});
