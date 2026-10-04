-- Back-office Seno v19 : bannière bloquant l'accès à l'app, et ciblage par version
-- (une version précise ou les versions inférieures).

alter table public.app_banners
  add column if not exists bloquer_acces boolean not null default false,
  add column if not exists version_cible text check (version_cible is null or version_cible ~ '^\d+(\.\d+){0,2}$'),
  add column if not exists version_mode text not null default 'egale' check (version_mode in ('egale', 'inferieure'));
