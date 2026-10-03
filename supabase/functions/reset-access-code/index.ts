import {
  adminClient, checkOtp, corsHeaders, hashAccessCode, isAccessCode, issueOtp, json, otpErrorResponse, randomToken,
  sha256Hex,
} from '../_shared/auth.ts';

const RESET_TTL_SECONDS = 15 * 60;
// Essais de date de naissance : 3, puis blocage 15 min, 1 h, 24 h, puis définitif
// (déblocage par le support) — appliqué par check_reset_birth_date en base

// Nouveau code d'accès pour l'utilisateur connecté :
// [check_birth_date] → start (date de naissance → SMS) → verify_otp → set_code
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  try {
    const admin = adminClient();
    const jwt = req.headers.get('Authorization')?.replace('Bearer ', '') ?? '';
    const { data: auth } = await admin.auth.getUser(jwt);
    if (!auth.user) return json({ error: 'unauthorized' }, 401);
    const userId = auth.user.id;

    const body = await req.json();

    const { data: access } = await admin
      .from('access_codes')
      .select('permanently_locked')
      .eq('user_id', userId)
      .maybeSingle();
    if (!access) return json({ error: 'unauthorized' }, 401);
    // Blocage définitif : seul le support peut débloquer
    if (access.permanently_locked) return json({ error: 'blocked' }, 403);

    // check_birth_date : date seule (aucun SMS) ; start : date puis SMS
    if (body.action === 'start' || body.action === 'check_birth_date') {
      if (
        typeof body.birth_date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(body.birth_date) ||
        Number.isNaN(Date.parse(body.birth_date))
      ) {
        return json({ error: 'invalid_request' }, 400);
      }
      // Comparaison et compteur d'essais atomiques (verrou de ligne en base)
      const { data: check, error: checkError } = await admin.rpc('check_reset_birth_date', {
        p_user: userId,
        p_date: body.birth_date,
      });
      if (checkError) throw checkError;
      const c = check as { ok?: true; error?: string; remaining?: number; retry_in?: number };
      if (c.error === 'unauthorized') return json({ error: 'unauthorized' }, 401);
      if (c.error === 'blocked') return json({ error: 'blocked' }, 403);
      if (c.error === 'locked') return json({ error: 'locked', retry_in: c.retry_in }, 429);
      if (c.error) return json({ error: 'birth_date_invalid', remaining: c.remaining }, 400);

      const { data: profile } = await admin
        .from('profiles').select('phone').eq('id', userId).maybeSingle();
      if (!profile?.phone) return json({ error: 'unauthorized' }, 401);

      if (body.action === 'check_birth_date') return json({ ok: true });

      const sms = await issueOtp(admin, profile.phone);
      if (sms.error === 'sms_failed') return json(sms, 502);

      // Une seule réinitialisation en cours par utilisateur
      await admin.from('access_code_resets').delete().eq('user_id', userId);
      const token = randomToken();
      const { error } = await admin.from('access_code_resets').insert({
        token_hash: await sha256Hex(token),
        user_id: userId,
        phone: profile.phone,
        expires_at: new Date(Date.now() + RESET_TTL_SECONDS * 1000).toISOString(),
      });
      if (error) throw error;
      return json({ token, phone: profile.phone });
    }

    // Étapes suivantes : jeton de réinitialisation obligatoire
    if (typeof body.token !== 'string') return json({ error: 'invalid_request' }, 400);
    const tokenHash = await sha256Hex(body.token);
    const { data: reset } = await admin
      .from('access_code_resets')
      .select('user_id, phone, otp_verified, expires_at')
      .eq('token_hash', tokenHash)
      .maybeSingle();
    if (!reset || reset.user_id !== userId || new Date(reset.expires_at).getTime() < Date.now()) {
      return json({ error: 'ticket_expired' }, 401);
    }

    if (body.action === 'resend') {
      const sms = await issueOtp(admin, reset.phone);
      if (sms.error) return json(sms, sms.error === 'sms_failed' ? 502 : 429);
      return json({ ok: true });
    }

    if (body.action === 'verify_otp') {
      if (typeof body.otp !== 'string' || !/^\d{4}$/.test(body.otp)) {
        return json({ error: 'invalid_request' }, 400);
      }
      const otpError = await checkOtp(admin, reset.phone, body.otp);
      if (otpError) return otpErrorResponse(otpError);
      await admin.from('access_code_resets').update({ otp_verified: true }).eq('token_hash', tokenHash);
      return json({ ok: true });
    }

    if (body.action === 'set_code') {
      if (!reset.otp_verified) return json({ error: 'ticket_expired' }, 401);
      if (!isAccessCode(body.code)) return json({ error: 'invalid_request' }, 400);

      const salt = randomToken(16);
      const { error } = await admin.from('access_codes').update({
        code_hash: await hashAccessCode(body.code, salt),
        salt,
        failed_attempts: 0,
        locked_until: null,
        lock_level: 0,
        updated_at: new Date().toISOString(),
      }).eq('user_id', userId);
      if (error) throw error;
      await admin.from('access_code_resets').delete().eq('token_hash', tokenHash);
      return json({ ok: true });
    }

    return json({ error: 'invalid_request' }, 400);
  } catch (e) {
    console.error('[reset-access-code]', e);
    return json({ error: 'server_error' }, 500);
  }
});
