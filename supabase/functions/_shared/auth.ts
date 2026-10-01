// Logique commune de l'authentification (téléphone + OTP SMS + code d'accès).
// Utilisé par send-otp, verify-otp, verify-access-code, set-access-code,
// unlock-app, reset-access-code et compte-otp.
import { SupabaseClient, createClient } from 'npm:@supabase/supabase-js@2';

export type { SupabaseClient };

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

// Côte d'Ivoire : +225 suivi de 10 chiffres commençant par 01, 05 ou 07
export function normalizePhone(input: unknown): string | null {
  if (typeof input !== 'string') return null;
  const phone = input.replace(/[\s-]/g, '');
  return /^\+225(01|05|07)\d{8}$/.test(phone) ? phone : null;
}

const toHex = (buf: ArrayBuffer) =>
  Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, '0')).join('');

export async function sha256Hex(value: string): Promise<string> {
  return toHex(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value)));
}

export async function hashCode(phone: string, code: string): Promise<string> {
  const pepper = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  return sha256Hex(`${phone}:${code}:${pepper}`);
}

export function randomToken(bytes = 32): string {
  return toHex(crypto.getRandomValues(new Uint8Array(bytes)).buffer);
}

/** Comparaison en temps constant (empreintes hexadécimales) */
export function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// Code d'accès : PBKDF2-SHA256 salé
export async function hashAccessCode(code: string, salt: string): Promise<string> {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(code), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', hash: 'SHA-256', salt: new TextEncoder().encode(salt), iterations: 100_000 },
    key,
    256,
  );
  return toHex(bits);
}

export const isAccessCode = (code: unknown): code is string =>
  typeof code === 'string' && /^\d{5}$/.test(code);

export function adminClient(): SupabaseClient {
  return createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false },
  });
}

// Ouvre une session : mot de passe aléatoire à usage unique puis connexion
export async function openSession(admin: SupabaseClient, userId: string, email: string) {
  const password = btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32))));
  const { error } = await admin.auth.admin.updateUserById(userId, { password });
  if (error) throw error;

  const anon = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
    auth: { persistSession: false },
  });
  const { data, error: signInError } = await anon.auth.signInWithPassword({ email, password });
  if (signInError || !data.session) throw signInError ?? new Error('no session');
  return { refresh_token: data.session.refresh_token, access_token: data.session.access_token };
}

// ---------- Comptes / code d'accès ----------

// E-mail technique interne : sert uniquement à ouvrir la session Supabase
export const internalEmail = (phone: string) => `${phone.replace('+', '')}@phone.seno.app`;

export async function findUserId(admin: SupabaseClient, phone: string): Promise<string | null> {
  const { data } = await admin.rpc('get_user_id_by_email', { p_email: internalEmail(phone) });
  return (data as string | null) ?? null;
}

export async function hasAccessCode(admin: SupabaseClient, userId: string): Promise<boolean> {
  const { data } = await admin.from('access_codes').select('user_id').eq('user_id', userId).maybeSingle();
  return !!data;
}

/** Ticket prouvant que le code d'accès a été validé pour cet utilisateur */
export async function isTicketValid(admin: SupabaseClient, ticket: unknown, userId: string): Promise<boolean> {
  if (typeof ticket !== 'string') return false;
  const { data } = await admin
    .from('login_tickets')
    .select('user_id, expires_at')
    .eq('ticket_hash', await sha256Hex(ticket))
    .maybeSingle();
  return !!data && data.user_id === userId && new Date(data.expires_at).getTime() > Date.now();
}

// ---------- Envoi et vérification de l'OTP par SMS ----------

const OTP_TTL_SECONDS = 300;

// Serveur SMS Sinexus (URL surchargeable via le secret SMS_API_URL)
const SMS_API_URL = Deno.env.get('SMS_API_URL') ?? 'https://sms.sinexus.tech/api/v1/send';
const SMS_API_KEY = Deno.env.get('SMS_API_KEY');

async function sendSms(to: string, body: string): Promise<void> {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' };
  if (SMS_API_KEY) headers.Authorization = `Bearer ${SMS_API_KEY}`;
  const res = await fetch(SMS_API_URL, { method: 'POST', headers, body: JSON.stringify({ to, body }) });
  if (!res.ok) throw new Error(`SMS API ${res.status}: ${await res.text()}`);
}

/** Génère, envoie et enregistre un OTP. Renvoie une erreur si anti-spam ou SMS en échec. */
export async function issueOtp(
  admin: SupabaseClient,
  phone: string,
): Promise<{ error?: 'rate_limited' | 'sms_failed'; retry_in?: number }> {
  // Anti-spam atomique : 1 SMS / 30 s et 5 SMS / heure par numéro
  const { data: wait, error: claimError } = await admin.rpc('claim_otp_send', { p_phone: phone });
  if (claimError) throw claimError;
  if ((wait as number) > 0) return { error: 'rate_limited', retry_in: wait as number };

  const code = String(crypto.getRandomValues(new Uint32Array(1))[0] % 10000).padStart(4, '0');

  // Envoi d'abord : si le SMS échoue, aucun code n'est enregistré
  try {
    await sendSms(phone, `Seno : votre code de connexion est ${code}. Il expire dans ${OTP_TTL_SECONDS / 60} minutes.`);
  } catch (e) {
    console.error('[issueOtp] envoi SMS échoué', e);
    return { error: 'sms_failed' };
  }

  // La ligne existe (claim_otp_send) : seuls le code et ses essais sont remplacés
  const { error } = await admin.from('phone_otps').update({
    code_hash: await hashCode(phone, code),
    expires_at: new Date(Date.now() + OTP_TTL_SECONDS * 1000).toISOString(),
    attempts: 0,
  }).eq('phone', phone);
  if (error) throw error;
  return {};
}

export type OtpError = 'code_expired' | 'too_many_attempts' | 'code_invalid';

/**
 * Vérifie un OTP. L'essai est réservé avant la comparaison (5 max par code,
 * même avec des requêtes simultanées) ; un code accepté est invalidé.
 */
export async function checkOtp(admin: SupabaseClient, phone: string, code: string): Promise<OtpError | null> {
  const { data, error } = await admin.rpc('claim_otp_attempt', { p_phone: phone });
  if (error) throw error;
  const claim = data as { code_hash?: string; error?: OtpError };
  if (claim.error) return claim.error;
  if (!safeEqual(claim.code_hash!, await hashCode(phone, code))) return 'code_invalid';
  const { error: consumeError } = await admin.rpc('consume_otp', { p_phone: phone });
  if (consumeError) throw consumeError;
  return null;
}

export const otpErrorResponse = (e: OtpError) => json({ error: e }, e === 'too_many_attempts' ? 429 : 400);

// ---------- Blocage progressif du code d'accès ----------
// 5 essais, puis 15 min, 1 h, 24 h ; blocage définitif (déblocage par le support)
// uniquement si allowPermanent (utilisateur déjà connecté) : sur la connexion
// anonyme, le seul numéro suffirait à bloquer définitivement un compte.

/**
 * Vérifie le code d'accès. L'essai est réservé avant la comparaison : au plus
 * 5 vérifications par fenêtre, même avec des requêtes simultanées.
 * Renvoie null si le code est bon, sinon la réponse d'erreur.
 */
export async function checkAccessCode(
  admin: SupabaseClient,
  userId: string,
  code: string,
  allowPermanent: boolean,
): Promise<Response | null> {
  const { data, error } = await admin.rpc('claim_access_attempt', { p_user: userId });
  if (error) throw error;
  const claim = data as {
    attempt?: number; code_hash?: string; salt?: string; error?: string; retry_in?: number;
  };
  if (claim.error === 'not_found') return json({ error: 'access_code_invalid' }, 400);
  if (claim.error === 'blocked') return json({ error: 'blocked' }, 403);
  if (claim.error === 'locked') return json({ error: 'locked', retry_in: claim.retry_in }, 429);

  if (safeEqual(claim.code_hash!, await hashAccessCode(code, claim.salt!))) {
    const { error: resetError } = await admin.from('access_codes').update({
      failed_attempts: 0,
      locked_until: null,
      lock_level: 0,
    }).eq('user_id', userId);
    if (resetError) throw resetError;
    return null;
  }

  const { data: failed, error: failError } = await admin.rpc('fail_access_attempt', {
    p_user: userId,
    p_attempt: claim.attempt,
    p_allow_permanent: allowPermanent,
  });
  if (failError) throw failError;
  const f = failed as { error: string; remaining?: number; retry_in?: number };
  if (f.error === 'blocked') return json({ error: 'blocked' }, 403);
  if (f.error === 'locked') return json({ error: 'locked', retry_in: f.retry_in }, 429);
  return json({ error: 'access_code_invalid', remaining: f.remaining }, 400);
}
