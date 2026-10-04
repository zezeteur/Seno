// Emails du back-office (Resend) : utilisés par `admin-reports` et `jeko-reconciliation`.
// Secrets : RESEND_API_KEY, REPORTS_FROM (ex. "Seno <alertes@seno.ci>"), BACKOFFICE_URL (optionnel).
import { EMAIL_LOGO_ATTACHMENT } from './email-logo.ts';

export const fcfa = (n: number) => `${new Intl.NumberFormat('fr-FR').format(n).replace(/ /g, ' ')} FCFA`;
export const esc = (s: unknown) =>
  String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);

export async function sendEmail(to: string[], subject: string, html: string): Promise<void> {
  const key = Deno.env.get('RESEND_API_KEY');
  const from = Deno.env.get('REPORTS_FROM');
  if (!key || !from) throw new Error('missing_env_RESEND_API_KEY_or_REPORTS_FROM');
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from, to, subject, html, attachments: [EMAIL_LOGO_ATTACHMENT] }),
  });
  if (!res.ok) throw new Error(`resend_${res.status}: ${await res.text()}`);
}

/** `path` : page du back-office ouverte par le bouton (ex. "/rapprochement") */
export function layout(title: string, body: string, path = ''): string {
  const url = Deno.env.get('BACKOFFICE_URL')?.replace(/\/+$/, '');
  return `<!doctype html><html><body style="margin:0;background:#f4f4f5;font-family:Arial,sans-serif;color:#18181b">
<div style="max-width:600px;margin:0 auto;padding:24px">
  <div style="background:#FDFE96;border-radius:12px 12px 0 0;padding:16px 24px"><img src="cid:seno-logo" alt="Seno" width="110" height="41" border="0" style="display:block;width:110px;height:41px;border:0"></div>
  <div style="background:#fff;border-radius:0 0 12px 12px;padding:24px">
    <h1 style="font-size:18px;margin:0 0 16px">${esc(title)}</h1>
    ${body}
    ${url ? `<p style="margin-top:24px"><a href="${esc(url + path)}" style="background:#18181b;color:#fff;padding:10px 16px;border-radius:8px;text-decoration:none">Ouvrir le back-office</a></p>` : ''}
  </div>
  <p style="font-size:12px;color:#71717a;text-align:center">Email automatique du back-office Seno.</p>
</div></body></html>`;
}

/** Destinataires valides des rapports (Paramètres → Rapports) */
export const validRecipients = (r: string[]) => r.filter((e) => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(e));
