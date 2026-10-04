-- Back-office Seno v21 : chronologie utilisateur paginée par numéro de page (décalage) au lieu d'un curseur de date.

drop function if exists public.admin_user_timeline(uuid, int, timestamptz, text[]);

create or replace function public.admin_user_timeline(
  p_user uuid, p_limit int default 50, p_offset int default 0, p_kinds text[] default null
)
returns table (at timestamptz, kind text, label text, details jsonb, ref text)
language sql stable security definer set search_path = '' as $$
  with mes_comptes as (select id from public.comptes where proprietaire = p_user),
  ev (created_at, kind, label, details, ref) as (
    select t.created_at, 'envoi'::text, coalesce(t.destinataire_label, t.numero_destination),
           jsonb_build_object('montant', t.montant, 'frais', t.frais, 'statut', t.statut, 'numero', t.numero_destination),
           t.id::text
      from public.transferts t where t.expediteur = p_user
    union all
    select t.created_at, 'reception', coalesce('@' || pr.pseudo, t.numero_source),
           jsonb_build_object('montant', t.montant, 'statut', t.statut, 'numero', t.numero_source),
           t.id::text
      from public.transferts t
      left join public.profiles pr on pr.id = t.expediteur
     where t.compte_destination in (select id from mes_comptes) and t.expediteur <> p_user
    union all
    select e.created_at, e.type, null, e.details, null from public.user_events e where e.user_id = p_user
    union all
    select a.created_at, 'support', a.action, a.details || jsonb_build_object('admin_id', a.admin_id), a.target_id
      from public.admin_audit_log a
     where (a.target_type = 'user' and a.target_id = p_user::text and a.action <> 'user.note')
        or (a.target_type = 'transfert' and a.target_id in (
              select id::text from public.transferts
               where expediteur = p_user or compte_destination in (select id from mes_comptes)))
    union all
    select n.created_at, 'note', n.canal, jsonb_build_object('contenu', n.contenu, 'admin_id', n.admin_id), null
      from public.user_notes n where n.user_id = p_user
  )
  select ev.created_at, ev.kind, ev.label, ev.details, ev.ref from ev
   where p_kinds is null or ev.kind = any (p_kinds)
   order by 1 desc
   limit least(greatest(p_limit, 1), 500)
  offset greatest(p_offset, 0);
$$;
revoke execute on function public.admin_user_timeline(uuid, int, int, text[]) from public, anon, authenticated;
