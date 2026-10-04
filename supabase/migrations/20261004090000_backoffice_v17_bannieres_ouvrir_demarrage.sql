-- Back-office Seno v17 : une seule bannière peut s'ouvrir en plein écran au démarrage de l'app.

alter table public.app_banners add column if not exists ouvrir_demarrage boolean not null default false;
create unique index if not exists app_banners_un_seul_demarrage on public.app_banners (ouvrir_demarrage) where ouvrir_demarrage;
