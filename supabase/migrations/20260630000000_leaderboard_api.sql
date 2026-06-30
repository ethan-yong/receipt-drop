-- Leaderboard API: RLS-enforced friend profile reads + security invoker RPC.
-- FastAPI impersonates authenticated users via JWT claims; Flutter RPC
-- fallback uses the same function under RLS.

create policy "profiles_select_accepted_friend"
  on public.profiles for select
  using (
    id = auth.uid()
    or exists (
      select 1
      from public.friendships f
      where f.status = 'accepted'
        and auth.uid() in (f.requester_id, f.addressee_id)
        and id in (f.requester_id, f.addressee_id)
    )
  );

-- security invoker: RLS on profiles/friendships enforces friend-only reads.
create or replace function public.get_friend_leaderboard()
returns table (
  user_id uuid,
  display_name text,
  avatar_config jsonb,
  current_mood text,
  badge_count int,
  current_streak int,
  is_me boolean
)
language sql
security invoker
set search_path = public
as $$
  select
    p.id,
    p.display_name,
    p.avatar_config,
    p.current_mood,
    p.badge_count,
    p.current_streak,
    p.id = auth.uid()
  from public.profiles p
  where p.id = auth.uid()
     or p.id in (
       select case when f.requester_id = auth.uid() then f.addressee_id else f.requester_id end
       from public.friendships f
       where f.status = 'accepted'
         and auth.uid() in (f.requester_id, f.addressee_id)
     )
  order by p.current_streak desc, p.badge_count desc;
$$;

grant execute on function public.get_friend_leaderboard() to authenticated;
