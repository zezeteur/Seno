import { adminClient, corsHeaders, hashCode, issueOtp, json, randomToken, sha256Hex } from './shared.ts';

const VERIFICATION_TTL_SECONDS = 10 * 60;
const MAX_OTP_ATTEMPTS = 5;
const COMPTE_COLUMNS = 'id, proprietaire, numero, id_reseau, created_at, updated_at';

// Ajout ou modification d'un compte mobile money :
// send (SMS au numéro saisi, compte_id pour une modification) → confirm (OTP → création / mise à jour)
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

    if (body.action === 'send') {
      const { numero, id_reseau } = body;
      if (typeof numero !== 'string' || !/^\d{10}$/.test(numero) || typeof id_reseau !== 'string') {
        return json({ error: 'invalid_request' }, 400);
      }
      const { data: reseau } = await admin
        .from('reseaux').select('id').eq('id', id_reseau).eq('statut', true).maybeSingle();
      if (!reseau) return json({ error: 'invalid_request' }, 400);

      // Modification : le compte doit appartenir à l'utilisateur et rester sur son réseau
      const compteId = typeof body.compte_id === 'string' ? body.compte_id : null;
      if (compteId) {
        const { data: own } = await admin
          .from('comptes').select('id_reseau')
          .eq('id', compteId).eq('proprietaire', userId).maybeSingle();
        if (!own || own.id_reseau !== id_reseau) return json({ error: 'invalid_request' }, 400);
      }

      const { data: existing } = await admin
        .from('comptes').select('id')
        .eq('proprietaire', userId).eq('numero', numero).eq('id_reseau', id_reseau)
        .maybeSingle();
      if (existing) return json({ error: 'compte_exists' }, 409);

      const sms = await issueOtp(admin, `+225${numero}`);
      if (sms.error) return json(sms, sms.error === 'sms_failed' ? 502 : 429);

      // Une seule vérification en cours par utilisateur
      await admin.from('compte_verifications').delete().eq('user_id', userId);
      const token = randomToken();
      const { error } = await admin.from('compte_verifications').insert({
        token_hash: await sha256Hex(token),
        user_id: userId,
        numero,
        id_reseau,
        compte_id: compteId,
        expires_at: new Date(Date.now() + VERIFICATION_TTL_SECONDS * 1000).toISOString(),
      });
      if (error) throw error;
      return json({ token });
    }

    // Étapes suivantes : jeton de vérification obligatoire
    if (typeof body.token !== 'string') return json({ error: 'invalid_request' }, 400);
    const tokenHash = await sha256Hex(body.token);
    const { data: verif } = await admin
      .from('compte_verifications')
      .select('user_id, numero, id_reseau, compte_id, expires_at')
      .eq('token_hash', tokenHash)
      .maybeSingle();
    if (!verif || verif.user_id !== userId || new Date(verif.expires_at).getTime() < Date.now()) {
      return json({ error: 'ticket_expired' }, 401);
    }
    const phone = `+225${verif.numero}`;

    if (body.action === 'resend') {
      const sms = await issueOtp(admin, phone);
      if (sms.error) return json(sms, sms.error === 'sms_failed' ? 502 : 429);
      return json({ ok: true });
    }

    if (body.action === 'confirm') {
      if (typeof body.otp !== 'string' || !/^\d{4}$/.test(body.otp)) {
        return json({ error: 'invalid_request' }, 400);
      }
      const { data: otp } = await admin
        .from('phone_otps').select('code_hash, expires_at, attempts').eq('phone', phone).maybeSingle();
      if (!otp || new Date(otp.expires_at).getTime() < Date.now()) {
        return json({ error: 'code_expired' }, 400);
      }
      if (otp.attempts >= MAX_OTP_ATTEMPTS) {
        await admin.from('phone_otps').delete().eq('phone', phone);
        return json({ error: 'too_many_attempts' }, 429);
      }
      if (otp.code_hash !== (await hashCode(phone, body.otp))) {
        await admin.from('phone_otps').update({ attempts: otp.attempts + 1 }).eq('phone', phone);
        return json({ error: 'code_invalid' }, 400);
      }
      await admin.from('phone_otps').delete().eq('phone', phone);

      // Modification (compte_id) ou création
      const { data: compte, error } = verif.compte_id
        ? await admin
            .from('comptes')
            .update({ numero: verif.numero, updated_at: new Date().toISOString() })
            .eq('id', verif.compte_id)
            .eq('proprietaire', userId)
            .select(COMPTE_COLUMNS)
            .single()
        : await admin
            .from('comptes')
            .insert({ proprietaire: userId, numero: verif.numero, id_reseau: verif.id_reseau })
            .select(COMPTE_COLUMNS)
            .single();
      if (error?.code === '23505') return json({ error: 'compte_exists' }, 409);
      if (error) throw error;

      if (body.set_as_default === true) {
        await admin.from('profiles')
          .update({ default_compte_id: compte.id, updated_at: new Date().toISOString() })
          .eq('id', userId);
      }
      await admin.from('compte_verifications').delete().eq('token_hash', tokenHash);
      return json({ compte });
    }

    return json({ error: 'invalid_request' }, 400);
  } catch (e) {
    console.error('[compte-otp]', e);
    return json({ error: 'server_error' }, 500);
  }
});
