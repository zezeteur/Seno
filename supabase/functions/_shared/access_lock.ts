// À ajouter à la fin de shared.ts (unlock-app et verify-access-code)
// ---------- Blocage progressif du code d'accès ----------

export const MAX_ACCESS_ATTEMPTS = 5;
// 15 min, puis 1 h, puis 24 h ; ensuite blocage définitif (déblocage par le support)
const LOCK_STEPS_SECONDS = [15 * 60, 60 * 60, 24 * 60 * 60];

export type AccessCodeRow = {
  code_hash: string;
  salt: string;
  failed_attempts: number;
  locked_until: string | null;
  lock_level: number;
  permanently_locked: boolean;
};

export const ACCESS_CODE_COLUMNS =
  'code_hash, salt, failed_attempts, locked_until, lock_level, permanently_locked';

/** Réponse d'erreur si le code d'accès est actuellement bloqué, sinon null */
export function lockResponse(access: AccessCodeRow): Response | null {
  if (access.permanently_locked) return json({ error: 'blocked' }, 403);
  const lockedMs = access.locked_until ? new Date(access.locked_until).getTime() - Date.now() : 0;
  if (lockedMs > 0) return json({ error: 'locked', retry_in: Math.ceil(lockedMs / 1000) }, 429);
  return null;
}

/** Enregistre une erreur ; bloque au 5e échec avec une durée croissante */
export async function registerFailedAttempt(
  admin: SupabaseClient,
  userId: string,
  access: AccessCodeRow,
): Promise<Response> {
  const failed = access.failed_attempts + 1;
  if (failed < MAX_ACCESS_ATTEMPTS) {
    await admin.from('access_codes').update({ failed_attempts: failed }).eq('user_id', userId);
    return json({ error: 'access_code_invalid', remaining: MAX_ACCESS_ATTEMPTS - failed }, 400);
  }

  const level = access.lock_level;
  if (level >= LOCK_STEPS_SECONDS.length) {
    await admin.from('access_codes').update({
      failed_attempts: 0,
      locked_until: null,
      permanently_locked: true,
    }).eq('user_id', userId);
    return json({ error: 'blocked' }, 403);
  }

  const seconds = LOCK_STEPS_SECONDS[level];
  await admin.from('access_codes').update({
    failed_attempts: 0,
    lock_level: level + 1,
    locked_until: new Date(Date.now() + seconds * 1000).toISOString(),
  }).eq('user_id', userId);
  return json({ error: 'locked', retry_in: seconds }, 429);
}

/** Code correct : remet les compteurs à zéro */
export async function resetAccessLock(admin: SupabaseClient, userId: string) {
  await admin.from('access_codes').update({
    failed_attempts: 0,
    locked_until: null,
    lock_level: 0,
  }).eq('user_id', userId);
}
