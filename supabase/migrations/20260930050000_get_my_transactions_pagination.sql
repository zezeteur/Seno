-- Historique paginé : curseur p_before (created_at de la dernière ligne reçue)
-- et filtre p_sens ('envoi' | 'reception' | null = tous).
drop function if exists public.get_my_transactions(int);

create function public.get_my_transactions(
  p_limit int default 50,
  p_before timestamptz default null,
  p_sens text default null
)
returns table (
  id uuid, sens text, label text, avatar_url text, montant integer, frais integer,
  statut text, created_at timestamptz, montant_recu integer, numero text, reseau_id uuid,
  payment_url text      -- envoi en attente de validation (Wave / Orange), sinon null
)
language sql
stable
security definer
set search_path = ''
as $$
  select * from (
    select t.id, 'envoi' as sens, coalesce(p.pseudo, t.destinataire_label), p.avatar_url,
           t.total, t.frais, t.statut, t.created_at,
           t.montant,
           -- Compte Seno d'un autre utilisateur : numéro masqué (07 •• •• 45 67)
           case when c.proprietaire is not null and c.proprietaire <> auth.uid()
                then left(t.numero_destination, 2) || ' •• •• '
                     || substr(t.numero_destination, 7, 2) || ' '
                     || substr(t.numero_destination, 9, 2)
                else t.numero_destination end,
           t.reseau_destination,
           case when t.statut = 'collecte_en_attente' then t.jeko_redirect_url end
    from public.transferts t
    left join public.comptes c on c.id = t.compte_destination
    left join public.profiles p on p.id = c.proprietaire
    where t.expediteur = auth.uid()
      and (p_sens is null or p_sens = 'envoi')
      and (p_before is null or t.created_at < p_before)

    union all

    select t.id, 'reception', p.pseudo, p.avatar_url,
           t.montant, 0, t.statut, t.created_at,
           t.montant, t.numero_destination, t.reseau_destination, null
    from public.transferts t
    join public.comptes c on c.id = t.compte_destination
    join public.profiles p on p.id = t.expediteur
    where c.proprietaire = auth.uid()
      and t.expediteur <> auth.uid()  -- envoi à soi-même : une seule ligne
      and t.statut = 'reussi'
      and (p_sens is null or p_sens = 'reception')
      and (p_before is null or t.created_at < p_before)
  ) x
  order by 8 desc
  limit least(greatest(p_limit, 1), 200);
$$;

revoke all on function public.get_my_transactions(int, timestamptz, text) from public, anon;
grant execute on function public.get_my_transactions(int, timestamptz, text) to authenticated;

-- Réceptions : recherche par compte de destination
create index if not exists transferts_compte_destination_idx
  on public.transferts (compte_destination, created_at desc);
