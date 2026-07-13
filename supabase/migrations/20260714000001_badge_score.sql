-- Phase 2: badge_score ranking signal, top-3 badge display on leaderboard rows.
-- Phase 1 (20260714000000_achievements.sql) added unlocked_tier and the trigger.
-- This migration adds badge_score to profiles, wires it into _refresh_achievement,
-- updates the three leaderboard RPCs, and flushes the Redis ZSET on deploy.

-- 1. Add badge_score to profiles; deprecate badge_count as ranking signal
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS badge_score int NOT NULL DEFAULT 0
  CONSTRAINT profiles_badge_score_nonneg CHECK (badge_score >= 0);

COMMENT ON COLUMN profiles.badge_count IS
  'DEPRECATED: use badge_score for ranking. Kept for backward compat; will be removed in a future migration.';

-- 2. Deterministic badge display priority (IMMUTABLE — safe to index/inline).
--    Priority 1 = most prominent. receipt_collector and food_explorer surface first
--    as broad-engagement signals; digital_tracker last because it is stubbed at 0.
CREATE OR REPLACE FUNCTION _badge_display_priority(p_badge_id text)
RETURNS int LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_badge_id
    WHEN 'receipt_collector'  THEN 1
    WHEN 'food_explorer'      THEN 2
    WHEN 'category_explorer'  THEN 3
    WHEN 'cafe_hopper'        THEN 4
    WHEN 'grocery_planner'    THEN 5
    WHEN 'digital_tracker'    THEN 6
    ELSE 99
  END;
$$;

-- 3. Reusable top-3 badges function called by both leaderboard RPCs.
--    Returns JSONB: [{badge_id, tier}, ...], empty array if no badges earned.
CREATE OR REPLACE FUNCTION get_user_top_badges(p_user_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object('badge_id', ub.badge_id, 'tier', ub.unlocked_tier)
      ORDER BY ub.unlocked_tier DESC,
               _badge_display_priority(ub.badge_id) ASC,
               ub.earned_at DESC
    ),
    '[]'::jsonb
  )
  FROM (
    SELECT badge_id, unlocked_tier, earned_at
    FROM user_badges
    WHERE user_id = p_user_id AND unlocked_tier > 0
    ORDER BY unlocked_tier DESC,
             _badge_display_priority(badge_id) ASC,
             earned_at DESC
    LIMIT 3
  ) ub;
$$;

GRANT EXECUTE ON FUNCTION get_user_top_badges(uuid) TO authenticated;

-- 4. Redefine _refresh_achievement to also maintain badge_score.
--    Body identical to 20260714000000_achievements.sql except the final UPDATE.
CREATE OR REPLACE FUNCTION _refresh_achievement(p_user_id uuid, p_key text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_progress int := 0;
  v_tier     int := 0;
BEGIN
  CASE p_key
    WHEN 'food_explorer' THEN
      SELECT COUNT(*) INTO v_progress FROM transactions
      WHERE user_id = p_user_id
        AND COALESCE(category_user, category_guess) = 'Food & Drink';

    WHEN 'cafe_hopper' THEN
      SELECT COUNT(*) INTO v_progress FROM transactions
      WHERE user_id = p_user_id
        AND LOWER(COALESCE(merchant_raw, '')) SIMILAR TO
            '%(coffee|cafe|starbucks|tealive|kopitiam|latte|boba)%';

    WHEN 'grocery_planner' THEN
      SELECT COUNT(*) INTO v_progress FROM transactions
      WHERE user_id = p_user_id
        AND COALESCE(category_user, category_guess) = 'Groceries';

    WHEN 'digital_tracker' THEN
      v_progress := 0; -- source_app not yet on transactions; stubbed

    WHEN 'receipt_collector' THEN
      SELECT COUNT(*) INTO v_progress FROM transactions
      WHERE user_id = p_user_id;

    WHEN 'category_explorer' THEN
      SELECT COUNT(DISTINCT COALESCE(category_user, category_guess))
      INTO v_progress FROM transactions
      WHERE user_id = p_user_id
        AND COALESCE(category_user, category_guess) IS NOT NULL
        AND COALESCE(category_user, category_guess) NOT IN ('Unclassified', '');

    ELSE RETURN;
  END CASE;

  -- Tier thresholds mirror badges-v1.json; update both when badge spec changes
  v_tier := CASE p_key
    WHEN 'food_explorer'     THEN CASE WHEN v_progress >= 50  THEN 3 WHEN v_progress >= 10 THEN 2 WHEN v_progress >= 3  THEN 1 ELSE 0 END
    WHEN 'cafe_hopper'       THEN CASE WHEN v_progress >= 30  THEN 3 WHEN v_progress >= 10 THEN 2 WHEN v_progress >= 3  THEN 1 ELSE 0 END
    WHEN 'grocery_planner'   THEN CASE WHEN v_progress >= 50  THEN 3 WHEN v_progress >= 10 THEN 2 WHEN v_progress >= 3  THEN 1 ELSE 0 END
    WHEN 'digital_tracker'   THEN CASE WHEN v_progress >= 50  THEN 3 WHEN v_progress >= 10 THEN 2 WHEN v_progress >= 3  THEN 1 ELSE 0 END
    WHEN 'receipt_collector' THEN CASE WHEN v_progress >= 100 THEN 3 WHEN v_progress >= 25 THEN 2 WHEN v_progress >= 5  THEN 1 ELSE 0 END
    WHEN 'category_explorer' THEN CASE WHEN v_progress >= 8   THEN 3 WHEN v_progress >= 5  THEN 2 WHEN v_progress >= 3  THEN 1 ELSE 0 END
    ELSE 0
  END;

  INSERT INTO user_badges (id, user_id, badge_id, progress, earned, earned_at, unlocked_tier, updated_at)
  VALUES (
    gen_random_uuid(),
    p_user_id,
    p_key,
    v_progress,
    (v_tier >= 1),
    CASE WHEN v_tier >= 1 THEN NOW() ELSE NULL END,
    v_tier,
    NOW()
  )
  ON CONFLICT (user_id, badge_id) DO UPDATE SET
    progress      = EXCLUDED.progress,
    earned        = EXCLUDED.earned,
    earned_at     = CASE
                      WHEN EXCLUDED.earned AND user_badges.earned_at IS NULL
                      THEN NOW()
                      ELSE user_badges.earned_at
                    END,
    unlocked_tier = EXCLUDED.unlocked_tier,
    updated_at    = NOW();

  UPDATE profiles SET
    badge_count = (SELECT COUNT(*) FROM user_badges WHERE user_id = p_user_id AND earned = true),
    badge_score = (SELECT COALESCE(SUM(unlocked_tier), 0) FROM user_badges WHERE user_id = p_user_id)
  WHERE id = p_user_id;
END;
$$;

-- 5. Update get_friend_leaderboard — add badge_score + top_badges, drop badge_count.
--    security invoker: RLS on profiles/friendships already enforces friend-only reads.
--    DROP required because Postgres rejects CREATE OR REPLACE when the return type changes.
DROP FUNCTION IF EXISTS public.get_friend_leaderboard();
CREATE FUNCTION public.get_friend_leaderboard()
RETURNS TABLE (
  user_id        uuid,
  display_name   text,
  avatar_config  jsonb,
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

-- 6. Update get_leaderboard_profiles_by_ids — add badge_score + top_badges, drop badge_count.
DROP FUNCTION IF EXISTS public.get_leaderboard_profiles_by_ids(uuid[]);
CREATE FUNCTION public.get_leaderboard_profiles_by_ids(p_user_ids uuid[])
RETURNS TABLE (
  user_id        uuid,
  display_name   text,
  avatar_config  jsonb,
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
    p.current_mood,
    p.badge_score,
    p.current_streak,
    get_user_top_badges(p.id)
  FROM public.profiles p
  WHERE p.id = ANY(p_user_ids);
$$;

GRANT EXECUTE ON FUNCTION public.get_leaderboard_profiles_by_ids(uuid[]) TO authenticated;

-- 7. Update list_leaderboard_scores — badge_score replaces badge_count for Redis rebuild.
DROP FUNCTION IF EXISTS public.list_leaderboard_scores();
CREATE FUNCTION public.list_leaderboard_scores()
RETURNS TABLE (user_id uuid, current_streak int, badge_score int)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT p.id, p.current_streak, p.badge_score
  FROM public.profiles p
  WHERE p.current_streak > 0 OR p.badge_score > 0;
$$;

REVOKE ALL ON FUNCTION public.list_leaderboard_scores() FROM public;
GRANT EXECUTE ON FUNCTION public.list_leaderboard_scores() TO postgres;

-- 8. Backfill badge_score for all existing users; validate no NULLs remain.
DO $$
DECLARE
  updated_count int;
BEGIN
  UPDATE profiles SET
    badge_score = COALESCE(
      (SELECT SUM(unlocked_tier) FROM user_badges WHERE user_id = profiles.id),
      0
    )
  WHERE badge_score = 0;
  GET DIAGNOSTICS updated_count = ROW_COUNT;
  RAISE NOTICE 'badge_score backfilled for % profile(s)', updated_count;

  IF EXISTS (SELECT 1 FROM profiles WHERE badge_score IS NULL) THEN
    RAISE EXCEPTION 'badge_score has NULL values after backfill';
  END IF;
END;
$$;

-- Deployment note: after applying this migration, run:
--   redis-cli DEL leaderboard:global
-- to flush the stale ZSET (old formula: streak × 1_000_000 + badge_count).
-- The leaderboard-api cold-start will rebuild it from list_leaderboard_scores()
-- using the new formula: (streak × 100) + badge_score.
