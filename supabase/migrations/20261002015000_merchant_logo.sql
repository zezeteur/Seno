-- Logo du commerce (facultatif) : fichier dans le bucket avatars, dossier de l'utilisateur
alter table public.merchant_requests add column if not exists logo_url text;
