-- Suppression du plafond journalier : restent le plafond par envoi et le
-- cumul mensuel.

create or replace function public.insert_transfert_plafonne(
  p_expediteur uuid,
  p_compte_source uuid,
  p_numero_source text,
  p_compte_destination uuid,
  p_destinataire_label text,
  p_numero_destination text,
  p_reseau_destination uuid,
  p_montant integer,
  p_frais integer,
  p_total integer,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_plafonds public.plafonds_transfert;
  v_mois timestamptz := date_trunc('month', now() at time zone 'UTC') at time zone 'UTC';
  v_mensuel bigint;
  v_id uuid;
begin
  perform pg_advisory_xact_lock(hashtextextended('plafond:' || p_expediteur::text, 0));

  select * into strict v_plafonds from public.plafonds_transfert where id = 1;
  if p_montant > v_plafonds.par_transaction then
    return jsonb_build_object('error', 'limit_exceeded', 'limit', 'transaction');
  end if;

  select coalesce(sum(montant), 0)
    into v_mensuel
    from public.transferts
   where expediteur = p_expediteur
     and statut not in ('collecte_echec', 'rembourse_en_cours', 'rembourse')
     and created_at >= v_mois;

  if v_mensuel + p_montant > v_plafonds.mensuel then
    return jsonb_build_object('error', 'limit_exceeded', 'limit', 'monthly');
  end if;

  insert into public.transferts (
    expediteur, compte_source, numero_source, compte_destination, destinataire_label,
    numero_destination, reseau_destination, montant, frais, total, idempotency_key
  ) values (
    p_expediteur, p_compte_source, p_numero_source, p_compte_destination, p_destinataire_label,
    p_numero_destination, p_reseau_destination, p_montant, p_frais, p_total, p_idempotency_key
  )
  returning id into v_id;

  return jsonb_build_object('id', v_id);
end;
$$;

-- Le type de retour change : la fonction est recréée
drop function public.get_my_plafond_usage();

create function public.get_my_plafond_usage()
returns table (mensuel bigint)
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(sum(montant), 0)
    from public.transferts
   where expediteur = (select auth.uid())
     and statut not in ('collecte_echec', 'rembourse_en_cours', 'rembourse')
     and created_at >= date_trunc('month', now() at time zone 'UTC') at time zone 'UTC';
$$;

revoke all on function public.get_my_plafond_usage() from public, anon;
grant execute on function public.get_my_plafond_usage() to authenticated;

-- Fraude « nouveau compte proche des plafonds » : cumul mensuel seul
create or replace function public.admin_fraud_scan()
returns table (user_id uuid, regle text, message text)
language plpgsql security definer set search_path = '' as $$
declare
  s public.fraud_settings;
  p public.plafonds_transfert;
  r record;
begin
  select * into s from public.fraud_settings where id = 1;
  if not found or not s.actif then return; end if;
  select * into p from public.plafonds_transfert where id = 1;

  -- 1. Beaucoup d'envois en peu de temps
  for r in
    select t.expediteur u, count(*) n from public.transferts t
     where t.created_at > now() - make_interval(mins => s.rafale_minutes)
     group by 1 having count(*) >= s.rafale_envois
  loop
    message := format('%s envois en %s min', r.n, s.rafale_minutes);
    if public.fraud_flag(r.u, 'rafale', message, jsonb_build_object('envois', r.n)) then
      user_id := r.u; regle := 'rafale'; return next;
    end if;
  end loop;

  -- 2. Nouveau compte qui atteint vite ses plafonds (mensuel)
  for r in
    select t.expediteur u,
           coalesce(sum(t.montant), 0) mois
      from public.transferts t
      join auth.users au on au.id = t.expediteur
     where au.created_at > now() - make_interval(days => s.nouveau_compte_jours)
       and t.created_at >= date_trunc('month', now())
       and t.statut not in ('collecte_echec', 'collecte_en_attente', 'rembourse')
     group by 1
    having coalesce(sum(t.montant), 0) >= p.mensuel * s.nouveau_compte_pct / 100.0
  loop
    message := format('Compte de moins de %s j : %s FCFA envoyés ce mois (plafond %s)',
                      s.nouveau_compte_jours, r.mois, p.mensuel);
    if public.fraud_flag(r.u, 'nouveau_plafond', message, jsonb_build_object('mois', r.mois)) then
      user_id := r.u; regle := 'nouveau_plafond'; return next;
    end if;
  end loop;

  -- 3. Plusieurs comptes sur le même appareil
  for r in
    select d.user_id u, x.n, x.token
      from (select da.token, count(distinct da.user_id) n from public.device_accounts da
             where da.last_seen > now() - make_interval(days => s.appareil_jours)
             group by da.token having count(distinct da.user_id) >= s.comptes_par_appareil) x
      join public.device_accounts d on d.token = x.token
     where d.last_seen > now() - make_interval(days => s.appareil_jours)
  loop
    message := format('%s comptes utilisés sur le même appareil', r.n);
    if public.fraud_flag(r.u, 'appareil_partage', message, jsonb_build_object('comptes', r.n, 'appareil', left(r.token, 12))) then
      user_id := r.u; regle := 'appareil_partage'; return next;
    end if;
  end loop;

  -- 4. Échecs de code d'accès en série
  for r in
    select e.user_id u, count(*) n from public.user_events e
     where e.type = 'echec_code' and e.created_at > now() - make_interval(hours => s.echecs_heures)
     group by 1 having count(*) >= s.echecs_code
  loop
    message := format('%s codes d''accès erronés en %s h', r.n, s.echecs_heures);
    if public.fraud_flag(r.u, 'echecs_code', message, jsonb_build_object('echecs', r.n)) then
      user_id := r.u; regle := 'echecs_code'; return next;
    end if;
  end loop;

  -- 5. Envois vers beaucoup de destinataires différents (24 h)
  for r in
    select t.expediteur u, count(distinct t.numero_destination) n from public.transferts t
     where t.created_at > now() - interval '24 hours'
     group by 1 having count(distinct t.numero_destination) >= s.destinataires_max
  loop
    message := format('Envois vers %s destinataires différents en 24 h', r.n);
    if public.fraud_flag(r.u, 'destinataires', message, jsonb_build_object('destinataires', r.n)) then
      user_id := r.u; regle := 'destinataires'; return next;
    end if;
  end loop;

  -- 6. Reçoit de beaucoup d'expéditeurs différents (24 h, hors boutiques) : compte « collecteur »
  for r in
    select c.proprietaire u, count(distinct t.expediteur) n from public.transferts t
      join public.comptes c on c.id = t.compte_destination
     where t.created_at > now() - interval '24 hours' and t.expediteur <> c.proprietaire
       and t.statut not in ('collecte_echec', 'collecte_en_attente')
       and not exists (select 1 from public.merchant_requests m where m.user_id = c.proprietaire and m.is_active)
     group by 1 having count(distinct t.expediteur) >= s.expediteurs_max
  loop
    message := format('Reçoit de %s expéditeurs différents en 24 h', r.n);
    if public.fraud_flag(r.u, 'expediteurs', message, jsonb_build_object('expediteurs', r.n)) then
      user_id := r.u; regle := 'expediteurs'; return next;
    end if;
  end loop;
end $$;

alter table public.plafonds_transfert drop column journalier;
