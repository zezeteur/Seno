import {
  ACCESS_CODE_COLUMNS, AccessCodeRow, adminClient, corsHeaders, findUserId, hashAccessCode, isAccessCode,
  issueOtp, json, lockResponse, normalizePhone, randomToken, registerFailedAttempt, resetAccessLock, sha256Hex,
} from './shared.ts';

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
    const { data } = userId
      ? await admin
          .from('access_codes')
          .select(ACCESS_CODE_COLUMNS)
          .eq('user_id', userId)
          .maybeSingle()
      : { data: null };
    if (!userId || !data) return json({ error: 'access_code_invalid' }, 400);
    const access = data as AccessCodeRow;

    // Même blocage que l'écran de verrouillage : se déconnecter ne le contourne pas
    const locked = lockResponse(access);
    if (locked) return locked;

    if (access.code_hash !== (await hashAccessCode(code, access.salt))) {
      return registerFailedAttempt(admin, userId, access);
    }

    await resetAccessLock(admin, userId);

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
