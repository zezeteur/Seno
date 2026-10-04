-- Back-office Seno v14 : texte du bouton de lien des bannières (« En savoir plus » par défaut).

alter table public.app_banners
  add column if not exists bouton_texte text check (bouton_texte is null or length(trim(bouton_texte)) between 1 and 30);
