-- Appareils connectés : sessions de l'utilisateur courant
create or replace function public.list_my_sessions()
returns table (
  id uuid,
  created_at timestamptz,
  last_active_at timestamptz,
  user_agent text,
  ip text,
  is_current boolean
)
language sql
security definer
set search_path = ''
stable
as $$
  select s.id,
         s.created_at,
         coalesce(s.refreshed_at::timestamptz, s.updated_at, s.created_at),
         s.user_agent,
         host(s.ip),
         s.id::text = (auth.jwt() ->> 'session_id')
  from auth.sessions s
  where s.user_id = auth.uid()
    and (s.not_after is null or s.not_after > now())
  order by s.id::text = (auth.jwt() ->> 'session_id') desc,
           coalesce(s.refreshed_at::timestamptz, s.updated_at, s.created_at) desc;
$$;

-- Révoque une autre session (jamais la session courante)
create or replace function public.revoke_my_session(p_session_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;
  if p_session_id::text = (auth.jwt() ->> 'session_id') then
    raise exception 'cannot_revoke_current_session';
  end if;
  delete from auth.sessions
  where id = p_session_id and user_id = auth.uid();
end;
$$;

revoke all on function public.list_my_sessions() from public, anon;
revoke all on function public.revoke_my_session(uuid) from public, anon;
grant execute on function public.list_my_sessions() to authenticated;
grant execute on function public.revoke_my_session(uuid) to authenticated;
