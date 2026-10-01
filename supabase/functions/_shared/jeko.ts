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

/** Reversement depuis le solde de la boutique vers le destinataire */
function createTransfer(p: {
  amount: number;
  reference: string;
  method: string;
  numero: string;
  name: string;
}) {
  return jeko<{ id: string; status: JekoStatus }>('POST', '/transfers', {
    storeId: env('JEKO_STORE_ID'),
    amountCents: p.amount * 100,
    currency: 'XOF',
    reference: p.reference,
    description: 'Envoi Seno',
    name: p.name,
    paymentMethod: p.method,
    identifier: { reference: `+225${p.numero}` },
  });
}

/** Référence Jèko ↔ envoi Seno : « seno-p-<uuid>-<n> » (collecte), « seno-t-<uuid> » (reversement) */
export const paymentReference = (id: string) => `seno-p-${id}-${Date.now().toString(36)}`;
export const transferReference = (id: string) => `seno-t-${id}`;

export function parseReference(ref: unknown): { kind: 'p' | 't'; id: string } | null {
  if (typeof ref !== 'string') return null;
  const m = /^seno-([pt])-([0-9a-f-]{36})/.exec(ref);
  return m ? { kind: m[1] as 'p' | 't', id: m[2] } : null;
}

export async function setStatus(admin: SupabaseClient, id: string, fields: Record<string, unknown>) {
  const { error } = await admin
    .from('transferts')
    .update({ ...fields, updated_at: new Date().toISOString() })
    .eq('id', id);
  if (error) throw error;
}

/** Collecte confirmée : lance le reversement une seule fois */
async function onPaymentSucceeded(admin: SupabaseClient, id: string): Promise<void> {
  const { data: claimed, error } = await admin.rpc('claim_transfert_payout', { p_id: id });
  if (error) throw error;
  if (!claimed) return; // déjà traité (webhook dupliqué ou suivi en parallèle)

  const { data: t, error: readError } = await admin
    .from('transferts')
    .select('montant, numero_destination, destinataire_label, reseaux:reseau_destination(abreviation)')
    .eq('id', id)
    .single();
  if (readError) throw readError;
  const abbr = (t.reseaux as unknown as { abreviation: string }).abreviation.toUpperCase();

  try {
    const transfer = await createTransfer({
      amount: t.montant,
      reference: transferReference(id),
      method: JEKO_METHODS[abbr],
      numero: t.numero_destination,
      name: t.destinataire_label,
    });
    await setStatus(admin, id, {
      jeko_transfer_id: transfer.id,
      ...(transfer.status === 'success' ? { statut: 'reussi' } : {}),
      ...(transfer.status === 'error' ? { statut: 'transfert_echec' } : {}),
    });
  } catch (e) {
    // Fonds collectés mais non reversés : reste visible pour traitement manuel
    await setStatus(admin, id, { statut: 'transfert_echec', erreur: (e as Error).message });
  }
}

/** Applique un statut Jèko (webhook ou suivi) à l'étape concernée */
export async function applyJekoStatus(
  admin: SupabaseClient,
  ref: { kind: 'p' | 't'; id: string },
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
  const { error } = await admin
    .from('transferts')
    .update({
      statut: status === 'success' ? 'reussi' : 'transfert_echec',
      erreur: status === 'success' ? null : (reason ?? 'transfer_failed'),
      updated_at: now,
    })
    .eq('id', ref.id)
    .eq('statut', 'transfert_en_cours');
  if (error) throw error;
}
