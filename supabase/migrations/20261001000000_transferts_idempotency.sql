-- Clé d'idempotence générée par l'app : un double tap ou un renvoi après
-- timeout réseau renvoie l'envoi existant au lieu d'en créer un second.
alter table public.transferts add column idempotency_key uuid;

create unique index transferts_expediteur_idempotency_key
  on public.transferts (expediteur, idempotency_key)
  where idempotency_key is not null;
