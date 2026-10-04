import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import { adminClient, getStoreBalance, json } from '../_shared/jeko.ts';
import { checkFcmAuth } from '../_shared/fcm.ts';
import { esc, layout, sendEmail, validRecipients } from '../_shared/mail.ts';

// Moteur de la page publique /status.
// Appelée par pg_cron (`status-check`, toutes les 5 min).
// Déployée sans vérification JWT : authentifiée par `x-cron-secret` (secret `cron_secret` du Vault).
//
// 1. Vérifie chaque composant (2 tentatives, délai max, seuil de lenteur) ;
// 2. enregistre l'état courant (service_status) et l'historique (service_checks) ;
// 3. gère les incidents : ouverture après 2 échecs consécutifs (10 min), aggravation, surveillance au
//    premier retour à la normale, résolution après 3 vérifications OK consécutives (15 min) ;
// 4. prévient les destinataires des alertes (Paramètres → Rapports) à l'ouverture, l'aggravation et la résolution.

type Etat = 'ok' | 'degrade' | 'panne';
type Resultat = { service: string; etat: Etat; latence_ms: number | null; detail: string | null };
type Incident = { id: string; service: string; titre: string; gravite: 'degrade' | 'panne'; phase: string; debut: string };

const LENT_MS = 3000;
const DELAI_MS = 10_000;
const ECHECS_OUVERTURE = 2;
const OK_RESOLUTION = 3;
const RANG: Record<Etat, number> = { ok: 0, degrade: 1, panne: 2 };

/** Noms publics des composants (repris par la page /status) */
const NOMS: Record<string, string> = {
  api: 'Application & base de données',
  auth: 'Connexion',
  sms: 'Codes SMS',
  paiements: 'Paiements mobile money',
  transferts: 'Envois d’argent',
  notifications: 'Notifications',
};
const nomDe = (service: string, reseaux: Map<string, string>) =>
  NOMS[service] ?? reseaux.get(service.replace(/^reseau:/, '')) ?? service;

class Degrade extends Error {}

/** Exécute une sonde avec 2 tentatives : un échec isolé (réseau, timeout) ne compte pas. */
async function sonder(service: string, fn: () => Promise<void>): Promise<Resultat> {
  let derniere: unknown;
  for (let tentative = 0; tentative < 2; tentative++) {
    const debut = Date.now();
    try {
      await fn();
      const latence_ms = Date.now() - debut;
      return { service, etat: latence_ms > LENT_MS ? 'degrade' : 'ok', latence_ms, detail: latence_ms > LENT_MS ? `lent_${latence_ms}ms` : null };
    } catch (e) {
      if (e instanceof Degrade) return { service, etat: 'degrade', latence_ms: Date.now() - debut, detail: e.message };
      derniere = e;
      if (tentative === 0) await new Promise((r) => setTimeout(r, 2000));
    }
  }
  console.error('status-check', service, derniere);
  return { service, etat: 'panne', latence_ms: null, detail: String((derniere as Error)?.message ?? derniere).slice(0, 300) };
}

/** Requête HTTP avec délai max ; `ok` décide si la réponse est acceptable */
async function http(url: string, init: RequestInit = {}, ok = (r: Response) => r.ok) {
  const res = await fetch(url, { ...init, signal: AbortSignal.timeout(DELAI_MS) });
  await res.body?.cancel();
  if (!ok(res)) throw new Error(`http_${res.status}`);
}

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const ANON = Deno.env.get('SUPABASE_ANON_KEY')!;
/** Démarrage d'une Edge Function (requête OPTIONS : aucun effet de bord) */
const fonction = (nom: string) =>
  http(`${SUPABASE_URL}/functions/v1/${nom}`, { method: 'OPTIONS', headers: { apikey: ANON, Origin: 'https://seno.ci' } });

type SanteReseau = { abreviation: string; nom: string; actif: boolean; total: number; ko: number; bloques: number };

/** Taux d'échec des transferts : perturbé au-delà du seuil des alertes, panne au-delà de 50 % */
function santeTransferts(total: number, ko: number, bloques: number, seuil: number, min: number) {
  if (total >= min && (100 * ko) / total >= 50) throw new Error(`echecs_${ko}/${total}`);
  if (total >= min && (100 * ko) / total >= seuil) throw new Degrade(`echecs_${ko}/${total}`);
  if (bloques >= 3) throw new Degrade(`bloques_${bloques}`);
}

async function verifier(db: SupabaseClient) {
  const [{ data: reseaux, error: e1 }, { data: reglages }] = await Promise.all([
    db.rpc('status_transferts'),
    db.from('report_settings').select('seuil_taux_echec, min_transferts_reseau').eq('id', 1).maybeSingle(),
  ]);
  const seuil = reglages?.seuil_taux_echec ?? 20;
  const min = reglages?.min_transferts_reseau ?? 10;
  const sante = (reseaux ?? []) as SanteReseau[];

  const smsUrl = Deno.env.get('SMS_API_URL') ?? 'https://sms.sinexus.tech/api/v1/send';

  const resultats = await Promise.all([
    sonder('api', async () => {
      if (e1) throw e1;
    }),
    sonder('auth', async () => {
      await Promise.all([
        http(`${SUPABASE_URL}/auth/v1/health`, { headers: { apikey: ANON } }),
        fonction('send-otp'),
        fonction('verify-otp'),
      ]);
    }),
    // Pas d'envoi de SMS : on vérifie seulement que le fournisseur répond (toute réponse < 500)
    sonder('sms', () => http(new URL(smsUrl).origin, {}, (r) => r.status < 500)),
    sonder('paiements', async () => {
      await getStoreBalance();
    }),
    sonder('transferts', async () => {
      await fonction('transfer');
      const actifs = sante.filter((r) => r.actif);
      santeTransferts(
        actifs.reduce((n, r) => n + r.total, 0),
        actifs.reduce((n, r) => n + r.ko, 0),
        actifs.reduce((n, r) => n + r.bloques, 0),
        seuil,
        min,
      );
    }),
    sonder('notifications', checkFcmAuth),
    // Opérateurs désactivés depuis le back-office : en maintenance, pas surveillés
    ...sante.filter((r) => r.actif).map((r) =>
      sonder(`reseau:${r.abreviation}`, async () => santeTransferts(r.total, r.ko, r.bloques, seuil, min))
    ),
  ]);

  // Secret absent : le composant n'est pas configuré (et non en panne) → pas surveillé
  return {
    resultats: resultats.filter((r) => !r.detail?.startsWith('missing_env_')),
    noms: new Map(sante.map((r) => [r.abreviation, r.nom])),
  };
}

// ---------------------------------------------------------------------------------------------
// Incidents
// ---------------------------------------------------------------------------------------------

const MESSAGES = {
  ouverture: (nom: string, g: Etat) =>
    g === 'panne'
      ? `Le service « ${nom} » est actuellement indisponible. Nos équipes ont été alertées et travaillent à son rétablissement.`
      : `Nous constatons des lenteurs ou des erreurs sur « ${nom} ». Nos équipes ont été alertées et enquêtent.`,
  aggravation: (nom: string) =>
    `La situation s'est aggravée : « ${nom} » est désormais indisponible. Nos équipes restent mobilisées.`,
  rechute: (nom: string) => `Le problème sur « ${nom} » est réapparu. Nos équipes poursuivent leurs investigations.`,
  surveillance: (nom: string) => `« ${nom} » se rétablit. Nous surveillons la situation de près.`,
  resolution: (nom: string, minutes: number) =>
    `L'incident est résolu : « ${nom} » fonctionne de nouveau normalement (durée : ${duree(minutes)}).`,
};

function duree(minutes: number) {
  if (minutes < 60) return `${minutes} min`;
  const h = Math.floor(minutes / 60);
  return minutes % 60 ? `${h} h ${minutes % 60} min` : `${h} h`;
}

const titreDe = (nom: string, g: Etat) => `${nom} : ${g === 'panne' ? 'indisponibilité' : 'service perturbé'}`;

type Evenement = { type: 'ouverture' | 'aggravation' | 'resolution'; titre: string; message: string };

async function gererIncidents(db: SupabaseClient, services: string[], noms: Map<string, string>) {
  const [{ data: ouverts, error }, ...historiques] = await Promise.all([
    db.from('status_incidents').select('id, service, titre, gravite, phase, debut').neq('phase', 'resolu'),
    ...services.map((s) =>
      db.from('service_checks').select('etat, checked_at').eq('service', s)
        .order('checked_at', { ascending: false }).limit(Math.max(ECHECS_OUVERTURE, OK_RESOLUTION))
    ),
  ]);
  if (error) throw error;

  const parService = new Map(((ouverts ?? []) as Incident[]).map((i) => [i.service, i]));
  // Un incident dont le composant n'est plus surveillé (opérateur désactivé) est clos
  for (const inc of parService.values()) if (!services.includes(inc.service)) services.push(inc.service);

  const evenements: Evenement[] = [];
  const maintenant = new Date().toISOString();

  const ajouterMaj = async (incidentId: string, phase: string, message: string) => {
    const { error } = await db.from('status_incident_updates').insert({ incident_id: incidentId, phase, message });
    if (error) throw error;
  };

  for (const [i, service] of services.entries()) {
    const recents = ((historiques[i]?.data ?? []) as { etat: Etat; checked_at: string }[]);
    const nom = nomDe(service, noms);
    const ouvert = parService.get(service);
    const echecs = recents.findIndex((c) => c.etat === 'ok');
    const nbEchecs = echecs === -1 ? recents.length : echecs;
    const nbOk = recents.findIndex((c) => c.etat !== 'ok') === -1 ? recents.length : recents.findIndex((c) => c.etat !== 'ok');
    const gravite: Etat = recents.slice(0, nbEchecs).reduce<Etat>((g, c) => (RANG[c.etat] > RANG[g] ? c.etat : g), 'ok');
    const suivi = historiques[i] !== undefined;

    if (!ouvert) {
      if (nbEchecs < ECHECS_OUVERTURE) continue;
      const titre = titreDe(nom, gravite);
      const { data: inc, error } = await db.from('status_incidents').insert({
        service, titre, gravite, phase: 'enquete', debut: recents[nbEchecs - 1].checked_at,
      }).select('id').single();
      if (error) throw error;
      const message = MESSAGES.ouverture(nom, gravite);
      await ajouterMaj(inc.id, 'enquete', message);
      evenements.push({ type: 'ouverture', titre, message });
      continue;
    }

    // Composant plus surveillé, ou rétabli depuis assez longtemps : résolution
    if (!suivi || nbOk >= OK_RESOLUTION) {
      const minutes = Math.max(1, Math.round((Date.now() - new Date(ouvert.debut).getTime()) / 60_000));
      const { error } = await db.from('status_incidents').update({ phase: 'resolu', fin: maintenant }).eq('id', ouvert.id);
      if (error) throw error;
      const message = MESSAGES.resolution(nom, minutes);
      await ajouterMaj(ouvert.id, 'resolu', message);
      evenements.push({ type: 'resolution', titre: ouvert.titre, message });
      continue;
    }

    if (nbOk > 0) {
      if (ouvert.phase === 'enquete') {
        const { error } = await db.from('status_incidents').update({ phase: 'surveillance' }).eq('id', ouvert.id);
        if (error) throw error;
        await ajouterMaj(ouvert.id, 'surveillance', MESSAGES.surveillance(nom));
      }
      continue;
    }

    // Toujours en échec
    if (RANG[gravite] > RANG[ouvert.gravite]) {
      const titre = titreDe(nom, gravite);
      const { error } = await db.from('status_incidents').update({ gravite, titre, phase: 'enquete' }).eq('id', ouvert.id);
      if (error) throw error;
      const message = MESSAGES.aggravation(nom);
      await ajouterMaj(ouvert.id, 'enquete', message);
      evenements.push({ type: 'aggravation', titre, message });
    } else if (ouvert.phase === 'surveillance') {
      const { error } = await db.from('status_incidents').update({ phase: 'enquete' }).eq('id', ouvert.id);
      if (error) throw error;
      await ajouterMaj(ouvert.id, 'enquete', MESSAGES.rechute(nom));
    }
  }
  return evenements;
}

/** Email aux destinataires des alertes ; un échec d'envoi ne bloque jamais le moteur */
async function notifier(db: SupabaseClient, evenements: Evenement[]) {
  if (!evenements.length) return;
  try {
    const { data } = await db.from('report_settings').select('recipients, alerts_enabled').eq('id', 1).maybeSingle();
    const to = validRecipients(data?.recipients ?? []);
    if (!data?.alerts_enabled || !to.length) return;
    const icone = { ouverture: '🔴', aggravation: '🔴', resolution: '✅' };
    const sujet = evenements.length === 1
      ? `${icone[evenements[0].type]} Seno · ${evenements[0].titre}${evenements[0].type === 'resolution' ? ' (résolu)' : ''}`
      : `⚠️ Seno · ${evenements.length} changements sur la page de statut`;
    await sendEmail(to, sujet, layout('Page de statut', `<ul style="padding-left:18px;font-size:14px;line-height:1.6">
      ${evenements.map((e) => `<li style="color:${e.type === 'resolution' ? '#16a34a' : '#dc2626'}">
        <strong>${esc(e.titre)}</strong><br>${esc(e.message)}</li>`).join('')}</ul>`, '/status'));
  } catch (e) {
    console.error('status-check notification', e);
  }
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
  const secret = req.headers.get('x-cron-secret') ?? '';

  try {
    const db = adminClient();
    const { data: ok, error: authError } = await db.rpc('check_cron_secret', { p_secret: secret });
    if (authError) throw authError;
    if (!secret || !ok) return json({ error: 'unauthorized' }, 401);

    const { resultats, noms } = await verifier(db);

    const checked_at = new Date().toISOString();
    const rows = resultats.map((r) => ({ ...r, checked_at }));
    const [{ error }, { error: histError }] = await Promise.all([
      db.from('service_status').upsert(rows),
      db.from('service_checks').insert(rows),
    ]);
    if (error) throw error;
    if (histError) throw histError;

    // Composants qui ne sont plus surveillés (opérateur désactivé) : retirés de l'état courant
    const suivis = resultats.map((r) => r.service);
    await db.from('service_status').delete().not('service', 'in', `(${suivis.map((s) => `"${s}"`).join(',')})`);

    const evenements = await gererIncidents(db, suivis, noms);
    await notifier(db, evenements);

    return json({ resultats: resultats.map(({ service, etat }) => ({ service, etat })), evenements: evenements.length });
  } catch (e) {
    console.error('status-check', e);
    return json({ error: 'internal' }, 500);
  }
});
