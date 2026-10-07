-- Demandes de paiement : expiration après 24 h (au lieu de 7 jours).
-- Les demandes existantes suivent la même règle à partir de leur création.
alter table public.payment_requests
  alter column expires_at set default now() + interval '24 hours';

update public.payment_requests
   set expires_at = created_at + interval '24 hours'
 where expires_at > created_at + interval '24 hours';
