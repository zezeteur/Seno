// Page de retour Jèko (successUrl / errorUrl) : redirige vers l'app sur l'envoi concerné.
// Déployé sans vérification JWT : n'expose rien, l'app recharge le statut elle-même.
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve((req) => {
  const url = new URL(req.url);
  const id = url.searchParams.get('t') ?? '';
  const status = url.searchParams.get('s') === 'success' ? 'success' : 'error';
  const target = UUID.test(id)
    ? `com.neotech.seno://payment/${id}?status=${status}`
    : 'com.neotech.seno://payment';
  return new Response(null, { status: 302, headers: { Location: target } });
});
