import {
  adminClient, checkOtp, corsHeaders, findUserId, hasAccessCode, internalEmail, isTicketValid, json, normalizePhone,
  openSession, otpErrorResponse, sha256Hex,
} from '../_shared/auth.ts';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  try {
    const { phone: rawPhone, code, ticket } = await req.json();
    const phone = normalizePhone(rawPhone);
    if (!phone || typeof code !== 'string' || !/^\d{4}$/.test(code)) {
      return json({ error: 'invalid_request' }, 400);
    }

    const admin = adminClient();
    let userId = await findUserId(admin, phone);

    // Compte avec code d'accès : le code d'accès doit avoir été validé avant
    const needsTicket = !!userId && (await hasAccessCode(admin, userId));
    if (needsTicket && !(await isTicketValid(admin, ticket, userId!))) {
      return json({ error: 'ticket_expired' }, 401);
    }

    const otpError = await checkOtp(admin, phone, code);
    if (otpError) return otpErrorResponse(otpError);

    // Code valide : ticket à usage unique
    if (needsTicket) {
      await admin.from('login_tickets').delete().eq('ticket_hash', await sha256Hex(ticket));
    }

    const email = internalEmail(phone);
    if (!userId) {
      const { data, error } = await admin.auth.admin.createUser({
        email,
        email_confirm: true,
        phone,
        phone_confirm: true,
      });
      if (error) throw error;
      userId = data.user.id;
    }

    const session = await openSession(admin, userId, email);
    const { data: profile } = await admin.from('profiles').select('id').eq('id', userId).maybeSingle();

    return json({ ...session, is_new_user: !profile });
  } catch (e) {
    console.error('[verify-otp]', e);
    return json({ error: 'server_error' }, 500);
  }
});
