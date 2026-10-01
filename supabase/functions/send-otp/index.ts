import {
  adminClient, corsHeaders, findUserId, hasAccessCode, isTicketValid, issueOtp, json, normalizePhone,
} from '../_shared/auth.ts';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  try {
    const { phone: rawPhone, ticket } = await req.json();
    const phone = normalizePhone(rawPhone);
    if (!phone) return json({ error: 'invalid_phone' }, 400);

    const admin = adminClient();

    // Compte existant avec code d'accès : le code d'accès d'abord, le SMS ensuite
    const userId = await findUserId(admin, phone);
    if (userId && (await hasAccessCode(admin, userId)) && !(await isTicketValid(admin, ticket, userId))) {
      return json({ requires_access_code: true });
    }

    const result = await issueOtp(admin, phone);
    if (result.error === 'rate_limited') return json(result, 429);
    if (result.error) return json(result, 502);
    return json({ ok: true });
  } catch (e) {
    console.error('[send-otp]', e);
    return json({ error: 'server_error' }, 500);
  }
});
