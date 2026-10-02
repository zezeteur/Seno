-- Le marchand modifie les infos de sa boutique (page « Ma boutique »).
-- Seules les colonnes d'infos sont modifiables : ni user_id ni status.
create policy "merchant_requests_update_own" on public.merchant_requests
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

revoke update on public.merchant_requests from authenticated;
grant update (business_name, pseudo, category, description, city, address,
  business_phone, email, logo_url)
  on public.merchant_requests to authenticated;
