-- Historique : ajoute le montant reçu, le numéro et le réseau de réception (écran de détail)
drop function if exists public.get_my_transactions(int);

create function public.get_my_transactions(p_limit int default 50)
returns table (
  id uuid,
  sens text,            -- 'envoi' | 'reception'
  label text,           -- pseudo de l'autre partie, sinon libellé / numéro saisi
  avatar_url text,
  montant integer,      -- débité (envoi, frais inclus) ou reçu (réception)
  frais integer,
  statut text,
  created_at timestamptz,
  montant_recu integer, -- reçu par le destinataire
  numero text,          -- numéro de réception
  reseau_id uuid        -- réseau de réception
)
language sql
stable
security definer
set search_path = ''
as $$
  select * from (
    select t.id, 'envoi', coalesce(p.pseudo, t.destinataire_label), p.avatar_url,
           t.total, t.frais, t.statut, t.created_at,
           t.montant,
           -- Compte Seno d'un autre utilisateur : numéro masqué (07 •• •• 45 67)
           case when c.proprietaire is not null and c.proprietaire <> auth.uid()
                then left(t.numero_destination, 2) || ' •• •• '
                     || substr(t.numero_destination, 7, 2) || ' '
                     || substr(t.numero_destination, 9, 2)
                else t.numero_destination end,
           t.reseau_destination
    from public.transferts t
    left join public.comptes c on c.id = t.compte_destination
    left join public.profiles p on p.id = c.proprietaire
    where t.expediteur = auth.uid()

    union all

    select t.id, 'reception', p.pseudo, p.avatar_url,
           t.montant, 0, t.statut, t.created_at,
           t.montant, t.numero_destination, t.reseau_destination
    from public.transferts t
    join public.comptes c on c.id = t.compte_destination
    join public.profiles p on p.id = t.expediteur
    where c.proprietaire = auth.uid()
      and t.expediteur <> auth.uid()  -- envoi à soi-même : une seule ligne
      and t.statut = 'reussi'
  ) x
  order by 8 desc
  limit least(greatest(p_limit, 1), 200);
$$;

revoke all on function public.get_my_transactions(int) from public, anon;
grant execute on function public.get_my_transactions(int) to authenticated;
