// Envoi Firebase Cloud Messaging (HTTP v1), même logique que src/lib/push.ts du back-office.
// Secret FCM_SERVICE_ACCOUNT : JSON du compte de service Firebase.
import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';

type ServiceAccount = { project_id: string; client_email: string; private_key: string };

const b64url = (data: string | ArrayBuffer) => {
  const bytes = typeof data === 'string' ? new TextEncoder().encode(data) : new Uint8Array(data);
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
};

async function accessToken(sa: ServiceAccount): Promise<string> {
  const pem = sa.private_key.replace(/-----[^-]+-----/g, '').replace(/\s/g, '');
  const key = await crypto.subtle.importKey(
    'pkcs8',
    Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))}.${b64url(JSON.stringify({
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }))}`;
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(unsigned));

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${unsigned}.${b64url(signature)}`,
    }),
  });
  if (!res.ok) throw new Error(`fcm_auth_${res.status}`);
  return (await res.json()).access_token;
}

/** Vérifie que Firebase accepte le compte de service (sans rien envoyer) : utilisé par status-check */
export async function checkFcmAuth(): Promise<void> {
  const raw = Deno.env.get('FCM_SERVICE_ACCOUNT');
  if (!raw) throw new Error('missing_env_FCM_SERVICE_ACCOUNT');
  await accessToken(JSON.parse(raw) as ServiceAccount);
}

export type PushMessage = { title: string; body: string; categorie: string };

/** Envoie à chaque token (8 en parallèle) et supprime les tokens invalides. */
export async function sendPush(db: SupabaseClient, tokens: string[], msg: PushMessage) {
  const raw = Deno.env.get('FCM_SERVICE_ACCOUNT');
  if (!raw) throw new Error('missing_env_FCM_SERVICE_ACCOUNT');
  const sa: ServiceAccount = JSON.parse(raw);
  const bearer = await accessToken(sa);
  const url = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;
  const dead: string[] = [];
  let sent = 0;

  const sendOne = async (token: string) => {
    const res = await fetch(url, {
      method: 'POST',
      headers: { Authorization: `Bearer ${bearer}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: msg.title, body: msg.body },
          data: { categorie: msg.categorie },
          android: { priority: 'high' },
        },
      }),
    });
    if (res.ok) sent++;
    // 404 UNREGISTERED / 400 INVALID_ARGUMENT : appli désinstallée ou token périmé
    else if (res.status === 404 || res.status === 400) dead.push(token);
  };

  for (let i = 0; i < tokens.length; i += 8) {
    await Promise.all(tokens.slice(i, i + 8).map(sendOne));
  }
  if (dead.length) await db.from('push_tokens').delete().in('token', dead);
  return { sent, failed: tokens.length - sent };
}
