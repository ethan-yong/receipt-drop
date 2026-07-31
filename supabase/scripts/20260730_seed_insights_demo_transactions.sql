-- One-time insights demo seed for ethanyong4616@gmail.com
-- (docs/plans/2026-07-28-ai-spending-insights.md — Option 2: insert transactions).
-- NOT a migration — deliberately kept out of supabase/migrations/ so it is never
-- re-applied automatically. Run manually against the target database:
--
--   npx supabase db query --linked -f supabase/scripts/20260730_seed_insights_demo_transactions.sql
--
-- (or paste into the Supabase Dashboard SQL editor with the service role).
--
-- Idempotent: fixed UUIDs a0000000-0000-4000-8000-000000000001 … 0023 are deleted
-- then re-inserted. Every merchant_raw is prefixed [INSIGHTS_SEED] for cleanup.
-- Dates are relative to now() so the script stays valid over time.
--
-- Shapes all five on-device detectors in lib/domain/logic/insight_detectors.dart:
--   habit           — 4 Tealive visits in 7 days (same place_id)
--   spending_spike  — 4 prior same-weekday RM20 baselines + today RM55
--   category_shift  — Food & Drink last week Mon RM50 → this week Mon RM110
--   streak          — receipts on today / yesterday / day-before (via habit rows)
--   forecast        — prior month RM400, current month pace projects ≥15% over

do $$
declare
  v_user_id uuid;
  v_today date := (timezone('utc', now()))::date;
  v_this_monday date := date_trunc('week', timezone('utc', now()))::date;
  v_last_monday date := v_this_monday - interval '7 days';
  v_prev_month_start date := date_trunc('month', timezone('utc', now()))::date - interval '1 month';
  v_curr_month_start date := date_trunc('month', timezone('utc', now()))::date;
  -- Fixed seed UUID namespace (a0000000-0000-4000-8000-000000000001 … 0023).
  v_seed_ids uuid[] := array[
    'a0000000-0000-4000-8000-000000000001'::uuid,
    'a0000000-0000-4000-8000-000000000002'::uuid,
    'a0000000-0000-4000-8000-000000000003'::uuid,
    'a0000000-0000-4000-8000-000000000004'::uuid,
    'a0000000-0000-4000-8000-000000000005'::uuid,
    'a0000000-0000-4000-8000-000000000006'::uuid,
    'a0000000-0000-4000-8000-000000000007'::uuid,
    'a0000000-0000-4000-8000-000000000008'::uuid,
    'a0000000-0000-4000-8000-000000000009'::uuid,
    'a0000000-0000-4000-8000-00000000000a'::uuid,
    'a0000000-0000-4000-8000-00000000000b'::uuid,
    'a0000000-0000-4000-8000-00000000000c'::uuid,
    'a0000000-0000-4000-8000-00000000000d'::uuid,
    'a0000000-0000-4000-8000-00000000000e'::uuid,
    'a0000000-0000-4000-8000-00000000000f'::uuid,
    'a0000000-0000-4000-8000-000000000010'::uuid,
    'a0000000-0000-4000-8000-000000000011'::uuid,
    'a0000000-0000-4000-8000-000000000012'::uuid,
    'a0000000-0000-4000-8000-000000000013'::uuid,
    'a0000000-0000-4000-8000-000000000014'::uuid,
    'a0000000-0000-4000-8000-000000000015'::uuid,
    'a0000000-0000-4000-8000-000000000016'::uuid,
    'a0000000-0000-4000-8000-000000000017'::uuid
  ];
begin
  select u.id
    into v_user_id
  from auth.users u
  where u.email = 'ethanyong4616@gmail.com';

  if v_user_id is null then
    raise exception
      'No auth.users row for ethanyong4616@gmail.com — create the account first';
  end if;

  if not exists (select 1 from public.profiles p where p.id = v_user_id) then
    raise exception
      'No profiles row for ethanyong4616@gmail.com — sign in once so the profile is created';
  end if;

  -- Idempotent cleanup of prior seed rows (and their dependent line-items/artifacts).
  delete from public.transactions
  where id = any (v_seed_ids);

  -- Clear curated insights for this user so the next InsightsWorker cycle can
  -- regenerate from the fresh detector pool (re-test curation from scratch).
  delete from public.spending_insights
  where user_id = v_user_id;

  insert into public.transactions (
    id,
    user_id,
    occurred_at,
    amount_myr,
    amount_source,
    needs_amount,
    merchant_raw,
    merchant_normalized,
    category_guess,
    category_confidence,
    place_status,
    place_google_place_id,
    place_name,
    place_lat,
    place_lng,
    place_confidence,
    pipeline_status
  )
  values
    -- ================================================================
    -- Habit (4 Tealive visits in 7 days) + streak coverage + today's spike
    -- ================================================================
    (
      'a0000000-0000-4000-8000-000000000001',
      v_user_id,
      (v_today + time '14:00') at time zone 'utc',
      55.00,
      'user',
      false,
      '[INSIGHTS_SEED] Tealive SS15',
      'tealive ss15',
      'Cafe',
      0.85,
      'guess',
      'seed-place-tealive',
      'Tealive SS15',
      3.0762,
      101.5854,
      0.9,
      'enriched'
    ),
    (
      'a0000000-0000-4000-8000-000000000002',
      v_user_id,
      (v_today - 1 + time '13:30') at time zone 'utc',
      12.50,
      'user',
      false,
      '[INSIGHTS_SEED] Tealive SS15',
      'tealive ss15',
      'Cafe',
      0.85,
      'guess',
      'seed-place-tealive',
      'Tealive SS15',
      3.0762,
      101.5854,
      0.9,
      'enriched'
    ),
    (
      'a0000000-0000-4000-8000-000000000003',
      v_user_id,
      (v_today - 2 + time '15:00') at time zone 'utc',
      12.50,
      'user',
      false,
      '[INSIGHTS_SEED] Tealive SS15',
      'tealive ss15',
      'Cafe',
      0.85,
      'guess',
      'seed-place-tealive',
      'Tealive SS15',
      3.0762,
      101.5854,
      0.9,
      'enriched'
    ),
    (
      'a0000000-0000-4000-8000-000000000004',
      v_user_id,
      (v_today - 4 + time '12:00') at time zone 'utc',
      12.50,
      'user',
      false,
      '[INSIGHTS_SEED] Tealive SS15',
      'tealive ss15',
      'Cafe',
      0.85,
      'guess',
      'seed-place-tealive',
      'Tealive SS15',
      3.0762,
      101.5854,
      0.9,
      'enriched'
    ),

    -- ================================================================
    -- Spending spike baselines: same weekday as today, 7/14/21/28 days ago
    -- ================================================================
    (
      'a0000000-0000-4000-8000-000000000005',
      v_user_id,
      (v_today - 7 + time '18:00') at time zone 'utc',
      20.00,
      'user',
      false,
      '[INSIGHTS_SEED] Shell Damansara',
      'shell damansara',
      'Transport',
      0.85,
      'guess',
      'seed-place-shell',
      'Shell Damansara',
      3.1357,
      101.6180,
      0.9,
      'enriched'
    ),
    (
      'a0000000-0000-4000-8000-000000000006',
      v_user_id,
      (v_today - 14 + time '18:00') at time zone 'utc',
      20.00,
      'user',
      false,
      '[INSIGHTS_SEED] Shell Damansara',
      'shell damansara',
      'Transport',
      0.85,
      'guess',
      'seed-place-shell',
      'Shell Damansara',
      3.1357,
      101.6180,
      0.9,
      'enriched'
    ),
    (
      'a0000000-0000-4000-8000-000000000007',
      v_user_id,
      (v_today - 21 + time '18:00') at time zone 'utc',
      20.00,
      'user',
      false,
      '[INSIGHTS_SEED] Shell Damansara',
      'shell damansara',
      'Transport',
      0.85,
      'guess',
      'seed-place-shell',
      'Shell Damansara',
      3.1357,
      101.6180,
      0.9,
      'enriched'
    ),
    (
      'a0000000-0000-4000-8000-000000000008',
      v_user_id,
      (v_today - 28 + time '18:00') at time zone 'utc',
      20.00,
      'user',
      false,
      '[INSIGHTS_SEED] Shell Damansara',
      'shell damansara',
      'Transport',
      0.85,
      'guess',
      'seed-place-shell',
      'Shell Damansara',
      3.1357,
      101.6180,
      0.9,
      'enriched'
    ),

    -- ================================================================
    -- Category shift: Food & Drink WoW (Mon last week 50 → Mon this week 110)
    -- ================================================================
    (
      'a0000000-0000-4000-8000-000000000009',
      v_user_id,
      (v_this_monday + time '12:00') at time zone 'utc',
      110.00,
      'user',
      false,
      '[INSIGHTS_SEED] Village Grocer',
      'village grocer',
      'Food & Drink',
      0.85,
      'guess',
      'seed-place-village',
      'Village Grocer',
      3.1123,
      101.6549,
      0.9,
      'enriched'
    ),
    (
      'a0000000-0000-4000-8000-00000000000a',
      v_user_id,
      (v_last_monday + time '12:00') at time zone 'utc',
      50.00,
      'user',
      false,
      '[INSIGHTS_SEED] Village Grocer',
      'village grocer',
      'Food & Drink',
      0.85,
      'guess',
      'seed-place-village',
      'Village Grocer',
      3.1123,
      101.6549,
      0.9,
      'enriched'
    ),

    -- ================================================================
    -- Forecast: prior calendar month total RM 400 (10 × RM 40)
    -- ================================================================
    (
      'a0000000-0000-4000-8000-00000000000b',
      v_user_id,
      (v_prev_month_start + 2 + time '10:00') at time zone 'utc',
      40.00,
      'user',
      false,
      '[INSIGHTS_SEED] AEON Big',
      'aeon big',
      'Groceries',
      0.85,
      'guess',
      'seed-place-aeon',
      'AEON Big',
      3.0489,
      101.6201,
      0.9,
      'enriched'
    ),
    (
      'a0000000-0000-4000-8000-00000000000c',
      v_user_id,
      (v_prev_month_start + 5 + time '10:00') at time zone 'utc',
      40.00,
      'user',
      false,
      '[INSIGHTS_SEED] AEON Big',
      'aeon big',
      'Groceries',
      0.85,
      'guess',
      'seed-place-aeon',
      'AEON Big',
      3.0489,
      101.6201,
      0.9,
      'enriched'
    ),
    (
      'a0000000-0000-4000-8000-00000000000d',
      v_user_id,
      (v_prev_month_start + 8 + time '10:00') at time zone 'utc',
      40.00,
      'user',
      false,
      '[INSIGHTS_SEED] AEON Big',
      'aeon big',
      'Groceries',
      0.85,
      'guess',
      'seed-place-aeon',
      'AEON Big',
      3.0489,
      101.6201,
      0.9,
      'enriched'
    ),
    (
      'a0000000-0000-4000-8000-00000000000e',
      v_user_id,
      (v_prev_month_start + 11 + time '10:00') at time zone 'utc',
      40.00,
      'user',
      false,
      '[INSIGHTS_SEED] MyNews',
      'mynews',
      'Food & Drink',
      0.85,
      'guess',
      'seed-place-mynews',
      'MyNews',
      3.0899,
      101.5950,
      0.9,
      'enriched'
    ),
    (
      'a0000000-0000-4000-8000-00000000000f',
      v_user_id,
      (v_prev_month_start + 14 + time '10:00') at time zone 'utc',
      40.00,
      'user',
      false,
      '[INSIGHTS_SEED] MyNews',
      'mynews',
      'Food & Drink',
      0.85,
      'guess',
      'seed-place-mynews',
      'MyNews',
      3.0899,
      101.5950,
      0.9,
      'enriched'
    ),
    (
      'a0000000-0000-4000-8000-000000000010',
      v_user_id,
      (v_prev_month_start + 17 + time '10:00') at time zone 'utc',
      40.00,
      'user',
      false,
      '[INSIGHTS_SEED] 7-Eleven Sunway',
      '7-eleven sunway',
      'Food & Drink',
      0.85,
      'guess',
      'seed-place-7e',
      '7-Eleven Sunway',
      3.0738,
      101.6067,
      0.9,
      'enriched'
    ),
    (
      'a0000000-0000-4000-8000-000000000011',
      v_user_id,
      (v_prev_month_start + 20 + time '10:00') at time zone 'utc',
      40.00,
      'user',
      false,
      '[INSIGHTS_SEED] 7-Eleven Sunway',
      '7-eleven sunway',
      'Food & Drink',
      0.85,
      'guess',
      'seed-place-7e',
      '7-Eleven Sunway',
      3.0738,
      101.6067,
      0.9,
      'enriched'
    ),
    (
      'a0000000-0000-4000-8000-000000000012',
      v_user_id,
      (v_prev_month_start + 23 + time '10:00') at time zone 'utc',
      40.00,
      'user',
      false,
      '[INSIGHTS_SEED] Uniqlo',
      'uniqlo',
      'Clothing',
      0.85,
      'guess',
      'seed-place-uniqlo',
      'Uniqlo',
      3.1579,
      101.7116,
      0.9,
      'enriched'
    ),
    (
      'a0000000-0000-4000-8000-000000000013',
      v_user_id,
      (v_prev_month_start + 26 + time '10:00') at time zone 'utc',
      40.00,
      'user',
      false,
      '[INSIGHTS_SEED] Uniqlo',
      'uniqlo',
      'Clothing',
      0.85,
      'guess',
      'seed-place-uniqlo',
      'Uniqlo',
      3.1579,
      101.7116,
      0.9,
      'enriched'
    ),
    (
      'a0000000-0000-4000-8000-000000000014',
      v_user_id,
      (least(v_prev_month_start + 28, v_curr_month_start - 1) + time '10:00')
        at time zone 'utc',
      40.00,
      'user',
      false,
      '[INSIGHTS_SEED] Grab',
      'grab',
      'Transport',
      0.85,
      'guess',
      'seed-place-grab',
      'Grab',
      3.1390,
      101.6869,
      0.9,
      'enriched'
    ),

    -- ================================================================
    -- Forecast fillers for current month — push pace above prior month
    -- Pattern rows already contribute ~RM 332+; these add RM 120 → ~452
    -- so projected EOM ≈ current/elapsed*daysInMonth clears 15% / RM30.
    -- ================================================================
    (
      'a0000000-0000-4000-8000-000000000015',
      v_user_id,
      (v_curr_month_start + 3 + time '11:00') at time zone 'utc',
      40.00,
      'user',
      false,
      '[INSIGHTS_SEED] Watsons',
      'watsons',
      'Health',
      0.85,
      'guess',
      'seed-place-watsons',
      'Watsons',
      3.1478,
      101.6953,
      0.9,
      'enriched'
    ),
    (
      'a0000000-0000-4000-8000-000000000016',
      v_user_id,
      (v_curr_month_start + 8 + time '11:00') at time zone 'utc',
      40.00,
      'user',
      false,
      '[INSIGHTS_SEED] Watsons',
      'watsons',
      'Health',
      0.85,
      'guess',
      'seed-place-watsons',
      'Watsons',
      3.1478,
      101.6953,
      0.9,
      'enriched'
    ),
    (
      'a0000000-0000-4000-8000-000000000017',
      v_user_id,
      (v_curr_month_start + 12 + time '11:00') at time zone 'utc',
      40.00,
      'user',
      false,
      '[INSIGHTS_SEED] Watsons',
      'watsons',
      'Health',
      0.85,
      'guess',
      'seed-place-watsons',
      'Watsons',
      3.1478,
      101.6953,
      0.9,
      'enriched'
    );

  raise notice 'Seeded % insight-demo transactions for user %',
    array_length(v_seed_ids, 1),
    v_user_id;
end $$;

-- ---------------------------------------------------------------------------
-- Verification
-- ---------------------------------------------------------------------------

select
  count(*) as seed_row_count,
  sum(amount_myr) as seed_total_myr,
  min(occurred_at) as earliest,
  max(occurred_at) as latest
from public.transactions
where id between
  'a0000000-0000-4000-8000-000000000001'::uuid
  and 'a0000000-0000-4000-8000-000000000017'::uuid;

select
  case
    when merchant_raw like '%Tealive%' then 'habit_tealive'
    when merchant_raw like '%Shell%' then 'spike_baseline'
    when merchant_raw like '%Village Grocer%' then 'category_shift'
    when occurred_at < date_trunc('month', timezone('utc', now()))
      then 'forecast_prior_month'
    else 'forecast_current_filler'
  end as pattern,
  count(*) as n,
  sum(amount_myr) as total_myr
from public.transactions
where merchant_raw like '[INSIGHTS_SEED]%'
group by 1
order by 1;

-- ---------------------------------------------------------------------------
-- Rollback (run manually to remove seed data only — does not touch other txs)
-- ---------------------------------------------------------------------------
-- delete from public.transactions
-- where id between
--   'a0000000-0000-4000-8000-000000000001'::uuid
--   and 'a0000000-0000-4000-8000-000000000017'::uuid;
--
-- delete from public.spending_insights si
-- using auth.users u
-- where si.user_id = u.id
--   and u.email = 'ethanyong4616@gmail.com';

-- ---------------------------------------------------------------------------
-- Client activation (after this script succeeds)
-- ---------------------------------------------------------------------------
-- 1. Clear app data / reinstall so hydrateFromCloudIfEmpty runs.
-- 2. Sign in as ethanyong4616@gmail.com.
-- 3. Wait up to ~55s after sign-in — hydrate triggers InsightsWorker directly
--    (seed rows have no receipt artifacts, so edit+Save cannot run SyncWorker).
-- 4. Check Home SpendingInsightsCard + detail charts.
--    Alternate: share/capture one real receipt (full SyncWorker path).
-- 5. Optional SQL check:
--    select insight_type, body, visualization
--    from public.spending_insights si
--    join auth.users u on u.id = si.user_id
--    where u.email = 'ethanyong4616@gmail.com'
--    order by rank;
