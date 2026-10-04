-- Back-office Seno v2 : clôture manuelle atomique d'un transfert.
-- Statut + note + journal d'audit dans une seule transaction, avec verrou de ligne :
-- deux admins ne peuvent pas clôturer le même transfert, et aucune clôture sans trace.
-- À exécuter après backoffice_admin.sql (SQL Editor ou supabase/migrations du repo Seno).

create or replace function public.admin_resolve_transfert(
  p_id uuid,
  p_admin uuid,
  p_statut text,
  p_note text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old text;
  v_note text := trim(coalesce(p_note, ''));
begin
  if p_statut not in ('reussi', 'rembourse') then
    raise exception 'invalid_statut' using errcode = '22023';
  end if;
  if char_length(v_note) < 5 then
    raise exception 'note_required' using errcode = '22023';
  end if;
  if not exists (select 1 from public.admins where user_id = p_admin and role = 'admin') then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select statut into v_old from public.transferts where id = p_id for update;
  if v_old is null then
    raise exception 'not_found' using errcode = 'P0002';
  end if;
  if v_old not in ('transfert_echec', 'remboursement_echec') then
    raise exception 'not_manual' using errcode = '55000';
  end if;

  update public.transferts
     set statut = p_statut,
         erreur = trim(both E'\n' from coalesce(erreur, '') || E'\n[back-office] ' || v_note),
         updated_at = now()
   where id = p_id;

  insert into public.admin_audit_log (admin_id, action, target_type, target_id, details)
  values (p_admin, 'transfert.resolve', 'transfert', p_id::text,
          jsonb_build_object('from', v_old, 'to', p_statut, 'note', v_note));

  return v_old;
end;
$$;

revoke all on function public.admin_resolve_transfert(uuid, uuid, text, text)
  from public, anon, authenticated;
