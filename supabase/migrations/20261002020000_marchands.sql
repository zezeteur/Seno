-- Compte marchand créé directement (plus de demande à valider).
-- Seule différence : les frais des paiements reçus sont payés par le marchand.
alter table public.merchant_requests rename to marchands;
alter table public.marchands drop column if exists status;
alter table public.marchands rename constraint merchant_requests_category_check
  to marchands_category_check;

drop policy if exists "merchant_requests_select_own" on public.marchands;
drop policy if exists "merchant_requests_insert_own" on public.marchands;

create policy "marchands_select_own" on public.marchands
  for select to authenticated using ((select auth.uid()) = user_id);

create policy "marchands_insert_own" on public.marchands
  for insert to authenticated with check ((select auth.uid()) = user_id);

-- Le destinataire (pseudo utilisateur ou pseudo boutique) est-il marchand ? Sert à l'affichage des frais.
create or replace function public.is_seno_merchant(p_pseudo text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.marchands m
    join public.profiles p on p.id = m.user_id
    where auth.uid() is not null
      and lower(trim(both from replace(p_pseudo, '@', ''))) in
        (lower(p.pseudo), lower(m.pseudo))
  );
$$;

revoke all on function public.is_seno_merchant(text) from public, anon;
grant execute on function public.is_seno_merchant(text) to authenticated;

-- Suivre le renommage : pseudos boutique et utilisateurs dans le même espace
alter index if exists public.merchant_requests_pseudo_key rename to marchands_pseudo_key;
create or replace function public.is_pseudo_available(p_pseudo text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not exists (
    select 1 from public.profiles where lower(pseudo) = lower(p_pseudo)
  ) and not exists (
    select 1 from public.marchands where lower(pseudo) = lower(p_pseudo)
  );
$$;

-- Comptes de réception : le pseudo boutique mène aux comptes du marchand
create or replace function public.get_seno_user_comptes(p_pseudo text)
returns table (id uuid, id_reseau uuid, numero_masque text, is_default boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_pseudo text := lower(trim(both from replace(p_pseudo, '@', '')));
begin
  if auth.uid() is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  return query
    select c.id,
           c.id_reseau,
           left(c.numero, 2) || ' •• •• ' || substr(c.numero, 7, 2) || ' '
             || substr(c.numero, 9, 2),
           c.id = p.default_compte_id
    from public.profiles p
    join public.comptes c on c.proprietaire = p.id
    where (lower(p.pseudo) = v_pseudo
           or p.id = (select m.user_id from public.marchands m
                      where lower(m.pseudo) = v_pseudo))
      and p.id <> auth.uid()
    order by c.id = p.default_compte_id desc, c.created_at;
end;
$$;
