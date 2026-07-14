-- Achievement system: Postgres-backed, event-driven
-- Progress is recomputed by a trigger on every transaction INSERT/UPDATE/DELETE.
-- Frontend reads user_badges via Supabase realtime (no client-side computation).

-- 1. Extend user_badges with tier tracking
ALTER TABLE user_badges
  ADD COLUMN IF NOT EXISTS unlocked_tier smallint NOT NULL DEFAULT 0;

-- 2. Core refresh function: recomputes one achievement for one user and upserts.
--    SECURITY DEFINER so the trigger (which runs as the transaction owner) can
--    write user_badges rows and update profiles.badge_count without RLS blocking.
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
      -- source_app not yet propagated to transactions; stubbed until follow-up
      v_progress := 0;

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
    -- Only stamp earned_at the first time a tier is earned; never clear it
    earned_at     = CASE
                      WHEN EXCLUDED.earned AND user_badges.earned_at IS NULL
                      THEN NOW()
                      ELSE user_badges.earned_at
                    END,
    unlocked_tier = EXCLUDED.unlocked_tier,
    updated_at    = NOW();

  -- Keep profiles.badge_count consistent for the friend leaderboard
  UPDATE profiles
  SET badge_count = (
    SELECT COUNT(*) FROM user_badges
    WHERE user_id = p_user_id AND earned = true
  )
  WHERE id = p_user_id;
END;
$$;

-- 3. Trigger function: refreshes all achievements for the affected user.
--    Inner BEGIN/EXCEPTION block prevents achievement errors from rolling back
--    the receipt mutation that fired the trigger.
CREATE OR REPLACE FUNCTION _trg_refresh_all_achievements()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_uid uuid := COALESCE(NEW.user_id, OLD.user_id);
BEGIN
  BEGIN
    PERFORM _refresh_achievement(v_uid, 'food_explorer');
    PERFORM _refresh_achievement(v_uid, 'cafe_hopper');
    PERFORM _refresh_achievement(v_uid, 'grocery_planner');
    PERFORM _refresh_achievement(v_uid, 'digital_tracker');
    PERFORM _refresh_achievement(v_uid, 'receipt_collector');
    PERFORM _refresh_achievement(v_uid, 'category_explorer');
  EXCEPTION WHEN OTHERS THEN
    NULL; -- never block the receipt mutation
  END;
  RETURN NULL; -- AFTER trigger; return value is ignored
END;
$$;

-- Fires on:
--   INSERT  → new receipt uploaded
--   UPDATE OF category_guess, category_user → enrichment filled category, or user edited it
--   DELETE  → receipt removed
DROP TRIGGER IF EXISTS trg_transactions_achievement_refresh ON transactions;
CREATE TRIGGER trg_transactions_achievement_refresh
AFTER INSERT OR UPDATE OF category_guess, category_user OR DELETE
ON transactions
FOR EACH ROW EXECUTE FUNCTION _trg_refresh_all_achievements();

-- 4. Enable realtime so Flutter clients receive push updates to user_badges
ALTER PUBLICATION supabase_realtime ADD TABLE user_badges;

-- 5. Backfill existing users (no-op for new installs with no transactions)
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT DISTINCT user_id FROM transactions LOOP
    PERFORM _refresh_achievement(r.user_id, 'food_explorer');
    PERFORM _refresh_achievement(r.user_id, 'cafe_hopper');
    PERFORM _refresh_achievement(r.user_id, 'grocery_planner');
    PERFORM _refresh_achievement(r.user_id, 'digital_tracker');
    PERFORM _refresh_achievement(r.user_id, 'receipt_collector');
    PERFORM _refresh_achievement(r.user_id, 'category_explorer');
  END LOOP;
END;
$$;
