-- Images : uniquement depuis notre stockage, dans le dossier de l'utilisateur.
-- Sinon une URL externe (pixel de pistage) révélait l'IP de quiconque affichait l'avatar.
-- ⚠ Domaine personnalisé : ajouter son préfixe ici avant de changer SUPABASE_URL dans l'app.
alter table public.profiles add constraint profiles_avatar_url_check check (
  avatar_url is null or avatar_url like
    'https://jbgnipiavizocgabelcn.supabase.co/storage/v1/object/public/avatars/' || id::text || '/%'
);

alter table public.merchant_requests add constraint merchant_requests_logo_url_check check (
  logo_url is null or logo_url like
    'https://jbgnipiavizocgabelcn.supabase.co/storage/v1/object/public/avatars/' || user_id::text || '/%'
);

-- Bucket public : images seulement (l'app envoie du JPEG), 5 Mo max
update storage.buckets
   set allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'],
       file_size_limit = 5242880
 where id = 'avatars';
