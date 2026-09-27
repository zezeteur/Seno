import {
  adminClient, corsHeaders, hashAccessCode, hashCode, isAccessCode, issueOtp, json, randomToken, sha256Hex,
} from './shared.ts';

const RESET_TTL_SECONDS = 15 * 60;
const MAX_BIRTH_DATE_ATTEMPTS = 3;
const BIRTH_DATE_LOCK_SECONDS = 24 * 60 * 60;
const MAX_OTP_ATTEMPTS = 5;

// Nouveau code d'accès pour l'utilisateur connecté :
// start (date de naissance → SMS) → verify_otp → set_code
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
      .select('permanently_locked, reset_failed_attempts, reset_locked_until')
      .eq('user_id', userId)
      .maybeSingle();
    if (!access) return json({ error: 'unauthorized' }, 401);
    // Blocage définitif : seul le support peut débloquer
    if (access.permanently_locked) return json({ error: 'blocked' }, 403);

    if (body.action === 'start') {
      const lockedMs = access.reset_locked_until
        ? new Date(access.reset_locked_until).getTime() - Date.now()
        : 0;
      if (lockedMs > 0) return json({ error: 'locked', retry_in: Math.ceil(lockedMs / 1000) }, 429);

      if (typeof body.birth_date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(body.birth_date)) {
        return json({ error: 'invalid_request' }, 400);
      }
      const { data: profile } = await admin
        .from('profiles')
        .select('date_naissance, phone')
        .eq('id', userId)
        .maybeSingle();
      if (!profile?.phone) return json({ error: 'unauthorized' }, 401);

      if (profile.date_naissance !== body.birth_date) {
        const failed = access.reset_failed_attempts + 1;
        if (failed >= MAX_BIRTH_DATE_ATTEMPTS) {
          await admin.from('access_codes').update({
            reset_failed_attempts: 0,
            reset_locked_until: new Date(Date.now() + BIRTH_DATE_LOCK_SECONDS * 1000).toISOString(),
          }).eq('user_id', userId);
          return json({ error: 'locked', retry_in: BIRTH_DATE_LOCK_SECONDS }, 429);
        }
        await admin.from('access_codes').update({ reset_failed_attempts: failed }).eq('user_id', userId);
        return json({ error: 'birth_date_invalid', remaining: MAX_BIRTH_DATE_ATTEMPTS - failed }, 400);
      }

      await admin.from('access_codes').update({ reset_failed_attempts: 0 }).eq('user_id', userId);

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
      const { data: otp } = await admin
        .from('phone_otps')
        .select('code_hash, expires_at, attempts')
        .eq('phone', reset.phone)
        .maybeSingle();
      if (!otp || new Date(otp.expires_at).getTime() < Date.now()) {
        return json({ error: 'code_expired' }, 400);
      }
      if (otp.attempts >= MAX_OTP_ATTEMPTS) {
        await admin.from('phone_otps').delete().eq('phone', reset.phone);
        return json({ error: 'too_many_attempts' }, 429);
      }
      if (otp.code_hash !== (await hashCode(reset.phone, body.otp))) {
        await admin.from('phone_otps').update({ attempts: otp.attempts + 1 }).eq('phone', reset.phone);
        return json({ error: 'code_invalid' }, 400);
      }
      await admin.from('phone_otps').delete().eq('phone', reset.phone);
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
