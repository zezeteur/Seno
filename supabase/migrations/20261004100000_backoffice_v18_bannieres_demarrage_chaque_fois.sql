-- Back-office Seno v18 : la bannière de démarrage s'ouvre une seule fois, ou à chaque lancement de l'app.

alter table public.app_banners add column if not exists demarrage_chaque_fois boolean not null default false;
