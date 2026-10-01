import { SupabaseClient, createClient } from 'npm:@supabase/supabase-js@2';

// QR codes de paiement Seno
//  - fixe     : SENO1:S:<jeton aléatoire>          (carte physique, régénérable)
//  - dynamique: SENO1:D:<jeton court aléatoire>     (dans l'app, expire en 90 s)
// Le scan est résolu uniquement ici : jamais d'identifiant utilisateur en clair.

const PREFIX = 'SENO1';
const DYNAMIC_TTL_SECONDS = 90;
const PAYEE_REF_TTL_SECONDS = 10 * 60;
const MAX_SCANS_PER_MINUTE = 30;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

const toHex = (buf: ArrayBuffer) =>
  Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, '0')).join('');

const b64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

// Clé AES dérivée d'un secret serveur (jamais présent dans l'app)
let aesKey: CryptoKey | null = null;
async function key(): Promise<CryptoKey> {
  if (aesKey) return aesKey;
  // Secret dédié obligatoire : jamais la clé service role en repli
  const secret = Deno.env.get('QR_SECRET')?.trim();
  if (!secret || secret.length < 32) throw new Error('missing_env_QR_SECRET');
  const raw = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`seno-qr-v1:${secret}`));
  aesKey = await crypto.subtle.importKey('raw', raw, 'AES-GCM', false, ['encrypt', 'decrypt']);
  return aesKey;
}

async function seal(data: Record<string, unknown>): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, await key(),
    new TextEncoder().encode(JSON.stringify(data)));
  const out = new Uint8Array(12 + ct.byteLength);
  out.set(iv);
  out.set(new Uint8Array(ct), 12);
  return b64url(out);
}

const newStaticToken = () => toHex(crypto.getRandomValues(new Uint8Array(16)).buffer);

async function staticToken(admin: SupabaseClient, userId: string, regenerate: boolean): Promise<string> {
  if (!regenerate) {
    const { data } = await admin.from('qr_static_codes').select('token').eq('user_id', userId).maybeSingle();
    if (data) return data.token;
  }
  const token = newStaticToken();
  const { error } = await admin.from('qr_static_codes')
    .upsert({ user_id: userId, token, created_at: new Date().toISOString() });
  if (error) throw error;
  return token;
}

// 07 01 02 03 04 → 07 •• •• •• 04
const maskNumero = (n: string) => `${n.slice(0, 2)} •• •• •• ${n.slice(-2)}`;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  try {
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const jwt = req.headers.get('Authorization')?.replace('Bearer ', '') ?? '';
    const { data: auth } = await admin.auth.getUser(jwt);
    if (!auth.user) return json({ error: 'unauthorized' }, 401);
    const userId = auth.user.id;

    const body = await req.json();

    if (body.action === 'static' || body.action === 'regenerate_static') {
      const token = await staticToken(admin, userId, body.action === 'regenerate_static');
      return json({ payload: `${PREFIX}:S:${token}` });
    }

    if (body.action === 'dynamic') {
      // Jeton court (96 bits, 16 caractères) : QR peu dense, facile à scanner
      const token = b64url(crypto.getRandomValues(new Uint8Array(12)));
      const expiresAt = new Date(Date.now() + DYNAMIC_TTL_SECONDS * 1000).toISOString();
      // Ménage : jetons expirés de cet utilisateur
      await admin.from('qr_dynamic_tokens').delete()
        .eq('user_id', userId).lt('expires_at', new Date().toISOString());
      const { error } = await admin.from('qr_dynamic_tokens')
        .insert({ token, user_id: userId, expires_at: expiresAt });
      if (error) throw error;
      return json({ payload: `${PREFIX}:D:${token}`, expires_at: expiresAt });
    }

    if (body.action === 'resolve') {
      // Anti-énumération : nombre de scans limité par minute
      const since = new Date(Date.now() - 60_000).toISOString();
      const { count } = await admin.from('qr_scan_log').select('id', { count: 'exact', head: true })
        .eq('user_id', userId).gte('created_at', since);
      if ((count ?? 0) >= MAX_SCANS_PER_MINUTE) return json({ error: 'rate_limited', retry_in: 60 }, 429);
      await admin.from('qr_scan_log').insert({ user_id: userId });

      const payload = typeof body.payload === 'string' ? body.payload.trim() : '';
      const [prefix, kind, token] = payload.split(':');
      if (prefix !== PREFIX || !token) return json({ error: 'qr_invalid' }, 400);

      let payeeId: string | null = null;
      if (kind === 'S' && /^[0-9a-f]{32}$/.test(token)) {
        const { data } = await admin.from('qr_static_codes').select('user_id').eq('token', token).maybeSingle();
        payeeId = data?.user_id ?? null;
      } else if (kind === 'D' && /^[A-Za-z0-9_-]{16}$/.test(token)) {
        const { data } = await admin.from('qr_dynamic_tokens')
          .select('user_id, expires_at').eq('token', token).maybeSingle();
        if (data && new Date(data.expires_at).getTime() < Date.now()) {
          return json({ error: 'qr_expired' }, 400);
        }
        payeeId = data?.user_id ?? null;
      }
      if (!payeeId) return json({ error: 'qr_invalid' }, 400);

      const { data: profile } = await admin.from('profiles')
        .select('pseudo, prenoms, avatar_url, default_compte_id').eq('id', payeeId).maybeSingle();
      if (!profile) return json({ error: 'qr_invalid' }, 400);

      let compte = null;
      if (profile.default_compte_id) {
        const { data } = await admin.from('comptes')
          .select('numero, reseaux(nom, abreviation)').eq('id', profile.default_compte_id).maybeSingle();
        const reseau = data?.reseaux as { nom: string; abreviation: string } | null;
        if (data && reseau) {
          compte = { numero_masque: maskNumero(data.numero), reseau: reseau.nom, abreviation: reseau.abreviation };
        }
      }

      return json({
        pseudo: profile.pseudo,
        prenom: String(profile.prenoms ?? '').trim().split(/\s+/)[0] ?? '',
        avatar_url: profile.avatar_url,
        compte,
        is_self: payeeId === userId,
        // Référence chiffrée du destinataire, pour le futur envoi d'argent
        payee_ref: await seal({ u: payeeId, e: Math.floor(Date.now() / 1000) + PAYEE_REF_TTL_SECONDS, t: 'p' }),
      });
    }

    return json({ error: 'invalid_request' }, 400);
  } catch (e) {
    console.error('[qr-code]', e);
    return json({ error: 'server_error' }, 500);
  }
});
