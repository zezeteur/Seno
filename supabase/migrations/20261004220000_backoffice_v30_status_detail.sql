-- Correctif v29 : service_status existait déjà (première version) et n'a pas reçu la colonne detail.
-- La page /status lit avec le service role : la policy de lecture publique n'a plus lieu d'être.

alter table public.service_status add column if not exists detail text;

drop policy if exists service_status_lecture on public.service_status;
revoke all on table public.service_status from anon, authenticated;
