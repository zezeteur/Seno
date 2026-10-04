-- Back-office Seno v15 : le bouton d'une bannière peut ouvrir une page de l'app au lieu d'un lien web.

alter table public.app_banners
  add column if not exists page_app text check (page_app is null or page_app in (
    'envoyer', 'encaisser', 'historique', 'statistiques', 'profil', 'securite',
    'plafonds', 'devenir_marchand', 'aide', 'notifications', 'parametres', 'appareils'
  )),
  add constraint app_banners_lien_ou_page check (lien is null or page_app is null);
