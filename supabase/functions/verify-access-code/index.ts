import {
  adminClient, checkAccessCode, corsHeaders, findUserId, isAccessCode, issueOtp, json, normalizePhone, randomToken,
  sha256Hex,
} from '../_shared/auth.ts';

const TICKET_TTL_SECONDS = 600;

// Étape 1 d'une connexion : code d'accès. Si correct → ticket + envoi de l'OTP.
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  try {
    const { phone: rawPhone, code } = await req.json();
    const phone = normalizePhone(rawPhone);
    if (!phone || !isAccessCode(code)) return json({ error: 'invalid_request' }, 400);

    const admin = adminClient();
    const userId = await findUserId(admin, phone);
    if (!userId) return json({ error: 'access_code_invalid' }, 400);

    // Même blocage que l'écran de verrouillage : se déconnecter ne le contourne pas.
    // Jamais de blocage définitif ici : il suffirait du numéro pour bloquer un compte.
    const denied = await checkAccessCode(admin, userId, code, false);
    if (denied) return denied;

    const ticket = randomToken();
    const { error } = await admin.from('login_tickets').insert({
      ticket_hash: await sha256Hex(ticket),
      user_id: userId,
      expires_at: new Date(Date.now() + TICKET_TTL_SECONDS * 1000).toISOString(),
    });
    if (error) throw error;

    // Anti-spam : si un SMS vient de partir, l'utilisateur utilisera celui-là
    const sms = await issueOtp(admin, phone);
    if (sms.error === 'sms_failed') return json(sms, 502);

    return json({ ticket });
  } catch (e) {
    console.error('[verify-access-code]', e);
    return json({ error: 'server_error' }, 500);
  }
});
