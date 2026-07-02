-- Global leaderboard: narrow security-definer reads for top-100 hydration
-- and cold-start ZSET rebuild. Does not open blanket profile SELECT via RLS.

create or replace function public.get_leaderboard_profiles_by_ids(p_user_ids uuid[])
returns table (
  user_id uuid,
  display_name text,
  avatar_config jsonb,
  current_mood text,
  badge_count int,
  current_streak int
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
    p.current_streak
  from public.profiles p
  where p.id = any(p_user_ids);
$$;

grant execute on function public.get_leaderboard_profiles_by_ids(uuid[]) to authenticated;

create or replace function public.list_leaderboard_scores()
returns table (
  user_id uuid,
  current_streak int,
  badge_count int
)
language sql
security definer
set search_path = public
as $$
  select p.id, p.current_streak, p.badge_count
  from public.profiles p
  where p.current_streak > 0 or p.badge_count > 0;
$$;

-- Rebuild only; called by FastAPI startup as postgres superuser.
revoke all on function public.list_leaderboard_scores() from public;
grant execute on function public.list_leaderboard_scores() to postgres;
