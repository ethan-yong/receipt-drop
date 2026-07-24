-- One-time backfill for `public.user_category_preferences`
-- (docs/plans/2026-07-23-feedback-learning-system.md), NOT a migration —
-- deliberately kept out of supabase/migrations/ so it's never re-applied
-- automatically. Run once, manually, against the target database after
-- 20260723020000_user_category_preferences.sql has been applied:
--
--   supabase db execute --file supabase/scripts/20260723_backfill_category_preferences.sql
--
-- (or paste into the SQL editor). Safe to re-run — `on conflict do nothing`
-- means it only ever seeds rows that don't already exist; it will never
-- overwrite a preference a real correction has since created or updated.
--
-- Derives free historical signal from every existing transaction where the
-- user's chosen category (`category_user`) already diverged from the
-- original guess (`category_guess`) — no new capture needed for this part.
-- `correction_count` is seeded from the number of qualifying transactions
-- for that (user, merchant) pair (each one *was* an independent instance of
-- the user overriding the guess), and the *most recent* divergent
-- transaction's category is used as the seeded value, consistent with the
-- "recency wins" rule the live `upsert_category_preference()` path applies
-- going forward.

insert into public.user_category_preferences (
  user_id, merchant_normalized, category, correction_count, last_corrected_at
)
select
  t.user_id,
  t.merchant_normalized,
  (array_agg(t.category_user order by t.occurred_at desc))[1] as category,
  count(*) as correction_count,
  max(t.occurred_at) as last_corrected_at
from public.transactions t
where t.category_user is not null
  and t.category_guess is not null
  and t.category_user <> t.category_guess
  and t.merchant_normalized is not null
  and t.merchant_normalized <> ''
group by t.user_id, t.merchant_normalized
on conflict (user_id, merchant_normalized) do nothing;
