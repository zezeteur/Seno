-- Seul le pseudo boutique déclenche la règle marchand : payer le compte
-- personnel du commerçant est un envoi classique (frais au choix)
create or replace function public.is_seno_merchant(p_pseudo text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.merchant_requests m
    where auth.uid() is not null
      and m.is_active
      and m.user_id <> auth.uid()
      and lower(trim(both from replace(p_pseudo, '@', ''))) = lower(m.pseudo)
  );
$$;

revoke all on function public.is_seno_merchant(text) from public, anon;
grant execute on function public.is_seno_merchant(text) to authenticated;
