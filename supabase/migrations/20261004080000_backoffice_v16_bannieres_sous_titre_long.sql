-- Back-office Seno v16 : sous-titre des bannières jusqu'à 1000 caractères (texte complet sur la page de détail).

alter table public.app_banners drop constraint app_banners_sous_titre_check;
alter table public.app_banners add constraint app_banners_sous_titre_check
  check (sous_titre is null or length(trim(sous_titre)) between 1 and 1000);
