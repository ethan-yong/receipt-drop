-- Surface the real profile photo on friend map pins (same reason as
-- 20260804010000_leaderboard_avatar_url.sql). DROP required because Postgres
-- rejects CREATE OR REPLACE when the return type gains a column.

DROP FUNCTION IF EXISTS public.get_friend_map_pins();
CREATE FUNCTION public.get_friend_map_pins()
RETURNS TABLE (
  user_id        uuid,
  display_name   text,
  avatar_config  jsonb,
  avatar_url     text,
  current_mood   text,
  place_name     text,
  lat            double precision,
  lng            double precision,
  occurred_at    timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT DISTINCT ON (t.user_id)
    t.user_id,
    p.display_name,
    p.avatar_config,
    p.avatar_url,
    p.current_mood,
    t.place_name,
    coalesce(t.place_lat, t.share_location_lat),
    coalesce(t.place_lng, t.share_location_lng),
    t.occurred_at
  FROM public.transactions t
  JOIN public.profiles p ON p.id = t.user_id
  WHERE coalesce(t.place_lat, t.share_location_lat) IS NOT NULL
    AND coalesce(t.place_lng, t.share_location_lng) IS NOT NULL
    AND t.occurred_at > now() - interval '30 days'
    AND p.share_map_location
    AND t.user_id IN (
      SELECT CASE WHEN f.requester_id = auth.uid()
                  THEN f.addressee_id ELSE f.requester_id END
      FROM public.friendships f
      WHERE f.status = 'accepted'
        AND auth.uid() IN (f.requester_id, f.addressee_id)
    )
  ORDER BY t.user_id, t.occurred_at DESC;
$$;

GRANT EXECUTE ON FUNCTION public.get_friend_map_pins() TO authenticated;
