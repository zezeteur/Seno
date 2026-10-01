import { adminClient, applyJekoStatus, json, parseReference } from '../_shared/jeko.ts';

// Webhook Jèko (TRANSACTION_COMPLETED, corps plat) : seule preuve de paiement / reversement.
// Déployé sans vérification JWT : authentifié par la signature HMAC-SHA256 (Jeko-Signature).
async function hmacHex(secret: string, body: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(body));
  return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  const raw = await req.text();
  const secret = Deno.env.get('JEKO_WEBHOOK_SECRET');
  const signature = req.headers.get('Jeko-Signature')?.trim().toLowerCase() ?? '';
  if (!secret || !safeEqual(signature, await hmacHex(secret, raw))) {
    return json({ error: 'invalid_signature' }, 401);
  }

  try {
    const tx = JSON.parse(raw);
    // Autres événements (ex. SERVICE_PROVIDER_LINK_REQUEST) : ignorés
    if (tx?.event) return json({ ok: true });

    const ref = parseReference(tx?.transactionDetails?.reference);
    if (!ref) return json({ ok: true }); // transaction hors Seno
    if (tx.status === 'success' || tx.status === 'error') {
      await applyJekoStatus(adminClient(), ref, tx.status, tx.errorReason ?? null);
    }
    return json({ ok: true });
  } catch (e) {
    console.error('jeko webhook', e);
    // 500 : Jèko relivrera ; le traitement est idempotent
    return json({ error: 'server_error' }, 500);
  }
});
