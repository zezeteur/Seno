-- Back-office Seno v13 : bannières avec titre, sous-titre et image (optionnels).
-- Le message devient le titre ; images dans le bucket public `banners`, envoyées par le back-office
-- (service role) uniquement.

alter table public.app_banners rename column message to titre;
alter table public.app_banners
  add column if not exists sous_titre text check (sous_titre is null or length(trim(sous_titre)) between 1 and 200),
  add column if not exists image_url text check (
    image_url is null or image_url like '%/storage/v1/object/public/banners/%'
  );

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('banners', 'banners', true, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;
