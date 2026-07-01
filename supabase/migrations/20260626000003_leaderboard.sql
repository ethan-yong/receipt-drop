-- Friend leaderboard. badge_count/current_streak are denormalized onto
-- profiles (same pattern as current_mood in the previous migration) rather
-- than aggregated live over other users' transactions/badges, so ranking
-- stays a flat join + order by with no per-request aggregation risk.

alter table public.profiles add column if not exists badge_count int not null default 0;
alter table public.profiles add column if not exists current_streak int not null default 0;

alter table public.profiles drop constraint if exists profiles_badge_count_nonneg;
alter table public.profiles add constraint profiles_badge_count_nonneg check (badge_count >= 0);

alter table public.profiles drop constraint if exists profiles_current_streak_nonneg;
alter table public.profiles add constraint profiles_current_streak_nonneg check (current_streak >= 0);

-- Ranking: current streak, then badge count (judgment call #8 — the
-- prototype's leaderboard order is hand-authored mock text, not computed;
-- this is a placeholder pending real product sign-off).
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
security definer
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
