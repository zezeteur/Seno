import { adminClient, corsHeaders, hashAccessCode, isAccessCode, json, randomToken } from '../_shared/auth.ts';

// Création du code d'accès (une seule fois, par l'utilisateur connecté)
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  try {
    const admin = adminClient();
    const jwt = req.headers.get('Authorization')?.replace('Bearer ', '') ?? '';
    const { data: auth } = await admin.auth.getUser(jwt);
    if (!auth.user) return json({ error: 'unauthorized' }, 401);

    const { code } = await req.json();
    if (!isAccessCode(code)) return json({ error: 'invalid_request' }, 400);

    const salt = randomToken(16);
    const { error } = await admin.from('access_codes').insert({
      user_id: auth.user.id,
      code_hash: await hashAccessCode(code, salt),
      salt,
    });
    // 23505 : un code existe déjà, on ne le remplace pas sans l'ancien
    if (error?.code === '23505') return json({ error: 'already_set' }, 409);
    if (error) throw error;

    return json({ ok: true });
  } catch (e) {
    console.error('[set-access-code]', e);
    return json({ error: 'server_error' }, 500);
  }
});
