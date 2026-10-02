// Client Jèko (Partner API) et logique commune des envois d'argent.
// Utilisé par les Edge Functions `transfer` et `jeko-webhook`.
import { createClient, type SupabaseClient } from 'jsr:@supabase/supabase-js@2';

export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

export function adminClient(): SupabaseClient {
  return createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false },
  });
}

const ENV_FORMATS: Record<string, RegExp> = {
  JEKO_API_URL: /^https:\/\/\S+$/,
  JEKO_STORE_ID: /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
  JEKO_SUCCESS_URL: /^https?:\/\/\S+$/,
  JEKO_ERROR_URL: /^https?:\/\/\S+$/,
};

/** Secret nettoyé (espaces, guillemets collés) et vérifié : erreur explicite sinon */
function env(name: string): string {
  const value = Deno.env.get(name)?.trim().replace(/^["']|["']$/g, '').trim();
  if (!value) throw new Error(`missing_env_${name}`);
  if (ENV_FORMATS[name] && !ENV_FORMATS[name].test(value)) throw new Error(`invalid_env_${name}`);
  return value;
}

/** Abréviation du réseau Seno → moyen de paiement Jèko */
export const JEKO_METHODS: Record<string, string> = {
  OM: 'orange',
  MTN: 'mtn',
  MOOV: 'moov',
  WAVE: 'wave',
};

export class JekoError extends Error {
  constructor(public status: number, public code: string, message: string) {
    super(message);
  }
}

async function jeko<T>(method: 'GET' | 'POST', path: string, body?: unknown): Promise<T> {
  const res = await fetch(`${env('JEKO_API_URL').replace(/\/+$/, '')}${path}`, {
    method,
    headers: {
      'X-API-KEY': env('JEKO_API_KEY'),
      'X-API-KEY-ID': env('JEKO_API_KEY_ID'),
      'Content-Type': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    // 422 : détail des champs refusés dans extras.errors
    console.error('jeko', method, path, res.status, JSON.stringify(data));
    throw new JekoError(res.status, data?.id ?? 'jeko_error', data?.message ?? res.statusText);
  }
  return data as T;
}

export type JekoStatus = 'pending' | 'success' | 'error';

/** Collecte sur le compte mobile money de l'expéditeur (USSD / redirection opérateur) */
export function createPaymentRequest(p: {
  amount: number;
  reference: string;
  method: string;
  numero: string;
}) {
  return jeko<{ id: string; status: JekoStatus; redirectUrl: string; errorReason?: string | null }>(
    'POST',
    '/payment_requests',
    {
      amountCents: p.amount * 100,
      currency: 'XOF',
      reference: p.reference,
      storeId: env('JEKO_STORE_ID'),
      paymentDetails: {
        type: 'redirect',
        data: {
          paymentMethod: p.method,
          payerPhone: `+225${p.numero}`,
          forceProviderDirect: true,
          successUrl: env('JEKO_SUCCESS_URL'),
          errorUrl: env('JEKO_ERROR_URL'),
        },
      },
    },
  );
}

export function getPaymentRequest(id: string) {
  return jeko<{ id: string; status: JekoStatus; errorReason?: string | null }>(
    'GET',
    `/payment_requests/${id}`,
  );
}

export function getTransfer(id: string) {
  return jeko<{ id: string; status: JekoStatus }>('GET', `/transfers/${id}`);
}


/** Envoi depuis le solde de la boutique (reversement au destinataire ou remboursement) */
function createTransfer(p: {
  amount: number;
  reference: string;
  method: string;
  numero: string;
  name: string;
  description: string;
}) {
  return jeko<{ id: string; status: JekoStatus }>('POST', '/transfers', {
    storeId: env('JEKO_STORE_ID'),
    amountCents: p.amount * 100,
    currency: 'XOF',
    reference: p.reference,
    description: p.description,
    name: p.name,
    paymentMethod: p.method,
    identifier: { reference: `+225${p.numero}` },
  });
}

/**
 * Référence Jèko ↔ envoi Seno :
 * « seno-p-<uuid>-<ts> » (collecte), « seno-t-<uuid>-<tentative> » (reversement),
 * « seno-r-<uuid> » (remboursement). Anciens reversements : « seno-t-<uuid> ».
 */
export const paymentReference = (id: string) => `seno-p-${id}-${Date.now().toString(36)}`;
const transferReference = (id: string, attempt: number) => `seno-t-${id}-${attempt}`;
const refundReference = (id: string) => `seno-r-${id}`;

export type JekoRef = { kind: 'p' | 't' | 'r'; id: string; attempt?: number };

export function parseReference(ref: unknown): JekoRef | null {
  if (typeof ref !== 'string') return null;
  const m = /^seno-([ptr])-([0-9a-f-]{36})(?:-(\d+))?/.exec(ref);
  if (!m) return null;
  const kind = m[1] as JekoRef['kind'];
  return { kind, id: m[2], attempt: kind === 't' && m[3] ? Number(m[3]) : undefined };
}

export async function setStatus(admin: SupabaseClient, id: string, fields: Record<string, unknown>) {
  const { error } = await admin
    .from('transferts')
    .update({ ...fields, updated_at: new Date().toISOString() })
    .eq('id', id);
  if (error) throw error;
}

// Reversement : 1 essai + 2 relances (après 2 puis 10 min), ensuite remboursement
const RETRY_DELAYS_MIN = [2, 10];

/** Collecte confirmée : lance le reversement une seule fois */
async function onPaymentSucceeded(admin: SupabaseClient, id: string): Promise<void> {
  const { data: claimed, error } = await admin.rpc('claim_transfert_payout', { p_id: id });
  if (error) throw error;
  if (!claimed) return; // déjà traité (webhook dupliqué ou suivi en parallèle)
  await launchPayout(admin, id);
}

/**
 * Lance une tentative de reversement (envoi déjà passé en `transfert_en_cours`).
 * Refus net de Jèko (4xx ou statut `error`) → relance ou remboursement.
 * Issue incertaine (réseau, 5xx) → `transfert_echec` : l'argent est peut-être
 * parti, on ne relance pas pour ne jamais payer deux fois.
 */
export async function launchPayout(admin: SupabaseClient, id: string): Promise<void> {
  const { data: t, error: readError } = await admin
    .from('transferts')
    .select('montant, numero_destination, destinataire_label, tentatives_reversement, reseaux:reseau_destination(abreviation)')
    .eq('id', id)
    .single();
  if (readError) throw readError;
  const abbr = (t.reseaux as unknown as { abreviation: string }).abreviation.toUpperCase();
  const attempt = t.tentatives_reversement + 1;
  await setStatus(admin, id, { tentatives_reversement: attempt, jeko_transfer_id: null });

  let transfer: { id: string; status: JekoStatus };
  try {
    transfer = await createTransfer({
      amount: t.montant,
      reference: transferReference(id, attempt),
      method: JEKO_METHODS[abbr],
      numero: t.numero_destination,
      name: t.destinataire_label,
      description: 'Envoi Seno',
    });
  } catch (e) {
    // `erreur` est renvoyée à l'app : code Jèko seulement, le détail reste dans les logs.
    console.error('jeko transfer', id, attempt, e);
    if (e instanceof JekoError && e.status < 500) return onPayoutFailed(admin, id, attempt, e.code);
    await setStatus(admin, id, {
      statut: 'transfert_echec',
      erreur: e instanceof JekoError ? e.code : 'transfer_unavailable',
    });
    return;
  }
  await setStatus(admin, id, {
    jeko_transfer_id: transfer.id,
    ...(transfer.status === 'success' ? { statut: 'reussi', erreur: null } : {}),
  });
  if (transfer.status === 'error') await onPayoutFailed(admin, id, attempt, 'transfer_failed');
}

/** Reversement refusé : relance programmée, ou remboursement après la dernière tentative */
async function onPayoutFailed(
  admin: SupabaseClient,
  id: string,
  attempt: number | undefined,
  reason: string,
): Promise<void> {
  const { data: t, error } = await admin
    .from('transferts').select('statut, tentatives_reversement').eq('id', id).single();
  if (error) throw error;
  // Échec d'une ancienne tentative (webhook en retard) ou déjà traité
  if (t.statut !== 'transfert_en_cours') return;
  if (attempt !== undefined && attempt !== t.tentatives_reversement) return;

  const delay = RETRY_DELAYS_MIN[t.tentatives_reversement - 1];
  if (delay !== undefined) {
    const { error: e } = await admin
      .from('transferts')
      .update({
        statut: 'reversement_relance',
        erreur: reason,
        prochaine_tentative: new Date(Date.now() + delay * 60_000).toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq('id', id)
      .eq('statut', 'transfert_en_cours')
      .eq('tentatives_reversement', t.tentatives_reversement);
    if (e) throw e;
    return;
  }
  await startRefund(admin, id, reason);
}

/** Échec définitif : rembourse `total` (montant + frais) sur le numéro source */
async function startRefund(admin: SupabaseClient, id: string, reason: string): Promise<void> {
  const { data: t, error } = await admin
    .from('transferts')
    .update({ statut: 'rembourse_en_cours', erreur: reason, updated_at: new Date().toISOString() })
    .eq('id', id)
    .eq('statut', 'transfert_en_cours')
    .select('total, numero_source, source:compte_source(reseaux:id_reseau(abreviation))')
    .maybeSingle();
  if (error) throw error;
  if (!t) return; // déjà pris en charge

  const abbr = (t.source as unknown as { reseaux: { abreviation: string } } | null)
    ?.reseaux.abreviation.toUpperCase();
  const method = abbr ? JEKO_METHODS[abbr] : undefined;
  if (!method) {
    // Compte source supprimé : réseau inconnu, remboursement manuel
    await setStatus(admin, id, { statut: 'remboursement_echec', erreur: 'refund_no_source' });
    return;
  }
  try {
    const refund = await createTransfer({
      amount: t.total,
      reference: refundReference(id),
      method,
      numero: t.numero_source,
      name: 'Client Seno',
      description: 'Remboursement Seno',
    });
    await setStatus(admin, id, {
      jeko_refund_id: refund.id,
      ...(refund.status === 'success' ? { statut: 'rembourse' } : {}),
      ...(refund.status === 'error' ? { statut: 'remboursement_echec', erreur: 'refund_failed' } : {}),
    });
  } catch (e) {
    console.error('jeko refund', id, e);
    await setStatus(admin, id, {
      statut: 'remboursement_echec',
      erreur: e instanceof JekoError ? e.code : 'refund_unavailable',
    });
  }
}

/** Applique un statut Jèko (webhook ou suivi) à l'étape concernée */
export async function applyJekoStatus(
  admin: SupabaseClient,
  ref: JekoRef,
  status: JekoStatus,
  reason?: string | null,
) {
  if (status === 'pending') return;
  const now = new Date().toISOString();
  if (ref.kind === 'p') {
    if (status === 'success') return onPaymentSucceeded(admin, ref.id);
    const { error } = await admin
      .from('transferts')
      .update({ statut: 'collecte_echec', erreur: reason ?? null, updated_at: now })
      .eq('id', ref.id)
      .eq('statut', 'collecte_en_attente');
    if (error) throw error;
    return;
  }
  if (ref.kind === 'r') {
    const { error } = await admin
      .from('transferts')
      .update({
        statut: status === 'success' ? 'rembourse' : 'remboursement_echec',
        ...(status === 'success' ? {} : { erreur: reason ?? 'refund_failed' }),
        updated_at: now,
      })
      .eq('id', ref.id)
      .eq('statut', 'rembourse_en_cours');
    if (error) throw error;
    return;
  }
  if (status === 'error') return onPayoutFailed(admin, ref.id, ref.attempt, reason ?? 'transfer_failed');
  const { error } = await admin
    .from('transferts')
    .update({ statut: 'reussi', erreur: null, updated_at: now })
    .eq('id', ref.id)
    .eq('statut', 'transfert_en_cours');
  if (error) throw error;
}
