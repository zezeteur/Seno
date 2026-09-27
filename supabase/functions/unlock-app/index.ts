import {
  ACCESS_CODE_COLUMNS, AccessCodeRow, adminClient, corsHeaders, hashAccessCode, isAccessCode, json,
  lockResponse, registerFailedAttempt, resetAccessLock,
} from './shared.ts';

// Déverrouillage de l'app : code d'accès de l'utilisateur connecté.
// En cas de blocage, la session est conservée : l'app reste sur l'écran de verrouillage.
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  try {
    const admin = adminClient();
    const jwt = req.headers.get('Authorization')?.replace('Bearer ', '') ?? '';
    const { data: auth } = await admin.auth.getUser(jwt);
    if (!auth.user) return json({ error: 'unauthorized' }, 401);
    const userId = auth.user.id;

    const { code } = await req.json();
    if (!isAccessCode(code)) return json({ error: 'invalid_request' }, 400);

    const { data } = await admin
      .from('access_codes')
      .select(ACCESS_CODE_COLUMNS)
      .eq('user_id', userId)
      .maybeSingle();
    if (!data) return json({ error: 'unauthorized' }, 401);
    const access = data as AccessCodeRow;

    const locked = lockResponse(access);
    if (locked) return locked;

    if (access.code_hash !== (await hashAccessCode(code, access.salt))) {
      return registerFailedAttempt(admin, userId, access);
    }

    await resetAccessLock(admin, userId);
    return json({ ok: true });
  } catch (e) {
    console.error('[unlock-app]', e);
    return json({ error: 'server_error' }, 500);
  }
});
