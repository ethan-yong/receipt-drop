-- Surface the real profile photo (profiles.avatar_url, now wired up by the
-- profile-setup/Settings screens) on the leaderboard, alongside the existing
-- stylized avatar_config fallback.
-- DROP required because Postgres rejects CREATE OR REPLACE when the return
-- type changes (same reason 20260714000001_badge_score.sql did this).

DROP FUNCTION IF EXISTS public.get_friend_leaderboard();
CREATE FUNCTION public.get_friend_leaderboard()
RETURNS TABLE (
  user_id        uuid,
  display_name   text,
  avatar_config  jsonb,
  avatar_url     text,
  current_mood   text,
  badge_score    int,
  current_streak int,
  top_badges     jsonb,
  is_me          boolean
)
LANGUAGE sql SECURITY INVOKER SET search_path = public AS $$
  SELECT
    p.id,
    p.display_name,
    p.avatar_config,
    p.avatar_url,
    p.current_mood,
    p.badge_score,
    p.current_streak,
    get_user_top_badges(p.id),
    p.id = auth.uid()
  FROM public.profiles p
  WHERE p.id = auth.uid()
     OR p.id IN (
       SELECT CASE WHEN f.requester_id = auth.uid()
                   THEN f.addressee_id ELSE f.requester_id END
       FROM public.friendships f
       WHERE f.status = 'accepted'
         AND auth.uid() IN (f.requester_id, f.addressee_id)
     )
  ORDER BY p.current_streak DESC, p.badge_score DESC;
$$;

GRANT EXECUTE ON FUNCTION public.get_friend_leaderboard() TO authenticated;

DROP FUNCTION IF EXISTS public.get_leaderboard_profiles_by_ids(uuid[]);
CREATE FUNCTION public.get_leaderboard_profiles_by_ids(p_user_ids uuid[])
RETURNS TABLE (
  user_id        uuid,
  display_name   text,
  avatar_config  jsonb,
  avatar_url     text,
  current_mood   text,
  badge_score    int,
  current_streak int,
  top_badges     jsonb
)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT
    p.id,
    p.display_name,
    p.avatar_config,
    p.avatar_url,
    p.current_mood,
    p.badge_score,
    p.current_streak,
    get_user_top_badges(p.id)
  FROM public.profiles p
  WHERE p.id = ANY(p_user_ids);
$$;

GRANT EXECUTE ON FUNCTION public.get_leaderboard_profiles_by_ids(uuid[]) TO authenticated;
