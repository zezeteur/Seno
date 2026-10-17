import { adminClient, corsHeaders, json } from '../_shared/jeko.ts';

// Préfixe commun des jetons : le scan reconnaît les appareils Seno
const TOKEN_PREFIX = '5e70a1b2';
const TOKEN_TTL_SECONDS = 180;
const MAX_RESOLVE = 20;
const TOKEN_PATTERN = /^5e70a1b2-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

// Envoi à proximité :
// - advertise : nouveau jeton éphémère à diffuser en BLE (remplace l'ancien)
// - resolve   : jetons captés → pseudo / prénoms / avatar (jamais soi-même)
// - stop      : supprime les jetons de l'utilisateur (page radar fermée)
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
    const now = new Date();

    switch (body.action) {
      case 'advertise': {
        // Un seul jeton actif par utilisateur ; ménage des jetons expirés
        await admin.from('nearby_tokens').delete().eq('user_id', userId);
        await admin.from('nearby_tokens').delete().lt('expires_at', now.toISOString());

        const token = TOKEN_PREFIX + crypto.randomUUID().slice(8);
        const expiresAt = new Date(now.getTime() + TOKEN_TTL_SECONDS * 1000);
        const { error } = await admin.from('nearby_tokens').insert({
          token,
          user_id: userId,
          expires_at: expiresAt.toISOString(),
        });
        if (error) throw error;
        return json({ token, expires_in: TOKEN_TTL_SECONDS });
      }

      case 'resolve': {
        const tokens = body.tokens;
        if (!Array.isArray(tokens) || tokens.length > MAX_RESOLVE) {
          return json({ error: 'invalid_request' }, 400);
        }
        const valid = [...new Set(tokens)]
          .filter((t): t is string => typeof t === 'string')
          .map((t) => t.toLowerCase())
          .filter((t) => TOKEN_PATTERN.test(t));
        if (valid.length === 0) return json({ people: [] });

        const { data: rows, error } = await admin
          .from('nearby_tokens').select('token, user_id')
          .in('token', valid).neq('user_id', userId)
          .gt('expires_at', now.toISOString());
        if (error) throw error;
        if (!rows?.length) return json({ people: [] });

        const { data: profiles, error: profilesError } = await admin
          .from('profiles').select('id, pseudo, prenoms, avatar_url')
          .in('id', rows.map((r) => r.user_id));
        if (profilesError) throw profilesError;
        const byId = new Map(profiles?.map((p) => [p.id, p]) ?? []);

        const people = rows.flatMap((r) => {
          const p = byId.get(r.user_id);
          if (!p?.pseudo) return [];
          return [{
            token: r.token,
            pseudo: p.pseudo,
            prenoms: p.prenoms ?? null,
            avatar_url: p.avatar_url ?? null,
          }];
        });
        return json({ people });
      }

      case 'stop': {
        await admin.from('nearby_tokens').delete().eq('user_id', userId);
        return json({ ok: true });
      }

      default:
        return json({ error: 'invalid_request' }, 400);
    }
  } catch (e) {
    console.error('nearby', e);
    return json({ error: 'server_error' }, 500);
  }
});
