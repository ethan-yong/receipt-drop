-- Post-rollout quality report for the merchant-intelligence layer
-- (docs/plans/2026-07-24-merchant-intelligence-layer.md and the accompanying
-- architecture review's "staged-rollout" step: "Enable Places-confirmed
-- entity writes, measure quality, then separately evaluate Places-call
-- optimization"). NOT a migration — deliberately kept out of
-- supabase/migrations/ so it is never auto-applied, matching the
-- 20260723_backfill_category_preferences.sql / 20260724_merchant_intelligence
-- _backfill_dry_run.sql precedent.
--
-- This script performs ZERO writes. It is meant to be run periodically
-- (manually) once `MERCHANT_INTELLIGENCE_MODE=on` has accumulated real
-- production traffic, to answer: "is the resolver actually improving
-- merchant identity quality, or just fragmenting the catalog?" It does not
-- decide anything on its own — every section is a report for a human to read
-- and act on (e.g. by adjusting the thresholds in
-- supabase/functions/_shared/merchant_resolution.ts, which are all named
-- exported constants specifically so they can be retuned without touching
-- the decision logic itself).
--
-- Run manually with any multi-statement-capable psql client (the installed
-- `supabase db query --file` CLI, as of v2.108, cannot run multi-statement
-- files — see the sibling backfill dry-run script's header for verified
-- alternatives, e.g. piping into the local Postgres container's own psql via
-- `docker exec`, or a real `psql` connection string against a linked/remote
-- project, or pasting into the Supabase Studio SQL editor).

begin;

set local pg_trgm.similarity_threshold = 0.45;

-- ---------------------------------------------------------------------------
-- 1. Resolution method breakdown: how transactions are actually being
--    resolved, and how confident each method's resolutions are. A healthy
--    rollout should show `exact_alias`/`fuzzy_brand` growing as a share of
--    total resolutions over time (the catalog "learning" repeat merchants)
--    rather than `places_search` staying flat at ~100% forever (which would
--    mean nothing is ever being recognized as a repeat).
-- ---------------------------------------------------------------------------
select
  coalesce(
    merchant_resolution_method,
    '(none - MI mode off/shadow, or not yet enriched)'
  ) as merchant_resolution_method,
  count(*) as transaction_count,
  round(avg(merchant_resolution_confidence)::numeric, 3) as avg_confidence,
  round(min(merchant_resolution_confidence)::numeric, 3) as min_confidence,
  round(max(merchant_resolution_confidence)::numeric, 3) as max_confidence
from public.transactions
group by 1
order by transaction_count desc;

-- ---------------------------------------------------------------------------
-- 2. Merchant catalog reuse health: how many merchants have ever been
--    "reattached to" (observation_count > 1) vs created once and never seen
--    again (observation_count = 1). A large and growing bucket of
--    observation_count = 1 merchants relative to total enrichment volume is
--    the primary fragmentation signal called out in the architecture
--    review's "Risks and Mitigations" — it means decideMerchantResolution()
--    is defaulting to create_new too often instead of attaching to an
--    existing brand.
-- ---------------------------------------------------------------------------
select
  case
    when observation_count = 1 then '1 (never reattached)'
    when observation_count between 2 and 4 then '2-4'
    when observation_count between 5 and 19 then '5-19'
    else '20+'
  end as observation_count_bucket,
  count(*) as merchant_count,
  sum(observation_count) as total_observations_in_bucket
from public.merchants
group by 1
order by min(observation_count);

-- ---------------------------------------------------------------------------
-- 3. Location catalog reuse health: same shape as (2) but for
--    merchant_locations.hit_count. A location with hit_count = 1 has only
--    ever matched once — expected for genuinely rare venues, but if the
--    overwhelming majority of locations never get a second hit, revisit
--    whether the alias fast-path and this table are overlapping/competing
--    rather than complementing each other.
-- ---------------------------------------------------------------------------
select
  case
    when hit_count = 1 then '1 (never re-hit)'
    when hit_count between 2 and 4 then '2-4'
    when hit_count between 5 and 19 then '5-19'
    else '20+'
  end as hit_count_bucket,
  count(*) as location_count,
  sum(hit_count) as total_hits_in_bucket
from public.merchant_locations
group by 1
order by min(hit_count);

-- ---------------------------------------------------------------------------
-- 4. Possible-duplicate-merchant detector (report only, never auto-merges —
--    same philosophy as the backfill dry-run script's fuzzy cross-place
--    section 4). Pairs of DISTINCT `merchants` rows whose normalized brand
--    text is textually very similar. Every row here is a candidate case
--    where decideMerchantResolution() should have attached to an existing
--    merchant but instead created a second one (e.g. a legal-suffix or
--    OCR-noise variant that fell just under BRAND_AGREEMENT_THRESHOLD, or a
--    genuine first-ever encounter with a brand that already existed in the
--    catalog under a slightly different spelling). Needs human judgment —
--    this script only surfaces candidates, matching the backfill script's
--    "report, don't resolve" stance for exactly the same reason (real
--    same-named-but-unrelated businesses are also possible).
-- ---------------------------------------------------------------------------
select
  a.id as merchant_id_a,
  a.canonical_name as name_a,
  a.observation_count as observation_count_a,
  b.id as merchant_id_b,
  b.canonical_name as name_b,
  b.observation_count as observation_count_b,
  similarity(a.normalized_name_key, b.normalized_name_key) as trigram_similarity
from public.merchants a
join public.merchants b
  on a.id < b.id
  and a.normalized_name_key % b.normalized_name_key
order by trigram_similarity desc, a.id, b.id;

-- ---------------------------------------------------------------------------
-- 5. New-merchant creation rate over time. Expected shape in a healthy
--    rollout: a rate that decays as the catalog matures (most merchants a
--    user population repeatedly visits get discovered early, so later days
--    should mostly attach to already-known merchants rather than minting new
--    ones). A rate that stays flat or grows linearly forever is the same
--    fragmentation signal as (2), viewed as a trend instead of a snapshot.
-- ---------------------------------------------------------------------------
select
  date_trunc('day', created_at) as day,
  count(*) as new_merchants_created
from public.merchants
group by 1
order by 1;

-- ---------------------------------------------------------------------------
-- 6. Correction-rate comparison: the plan's own specified success metric
--    ("User correction reduction... recommend tracking correction rate per
--    merchant as a post-launch rollout-validation metric" - see "Testing
--    Strategy" in docs/plans/2026-07-24-merchant-intelligence-layer.md).
--    Compares the merchant-field correction rate (from
--    user_field_corrections) between enriched transactions that got a
--    merchant-intelligence link (merchant_id is not null) and those that
--    didn't (mode was off/shadow, or MI reconciliation didn't fire for that
--    transaction). A materially LOWER correction rate for the
--    merchant_id-linked group is the headline signal that this feature is
--    actually reducing user corrections rather than just adding catalog
--    bookkeeping.
-- ---------------------------------------------------------------------------
with tx_group as (
  select id, (merchant_id is not null) as has_merchant_link
  from public.transactions
  where pipeline_status = 'enriched'
),
merchant_corrections as (
  select distinct transaction_id
  from public.user_field_corrections
  where field = 'merchant'
)
select
  t.has_merchant_link,
  count(*) as enriched_transaction_count,
  count(c.transaction_id) as merchant_correction_count,
  round(
    100.0 * count(c.transaction_id) / nullif(count(*), 0),
    2
  ) as correction_rate_pct
from tx_group t
left join merchant_corrections c on c.transaction_id = t.id
group by t.has_merchant_link
order by t.has_merchant_link;

rollback;
