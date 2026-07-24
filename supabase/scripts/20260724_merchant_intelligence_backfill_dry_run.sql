-- Read-only dry-run report for a *future* merchant-intelligence historical
-- backfill (docs/plans/2026-07-24-merchant-intelligence-layer.md, and the
-- accompanying architecture review's "Implementation Plan" step 7 / "Testing
-- Strategy" backfill-validation bullet / "Risks and Mitigations" backfill
-- entry). NOT a migration — deliberately kept out of supabase/migrations/ so
-- it is never auto-applied, matching the existing
-- supabase/scripts/20260723_backfill_category_preferences.sql precedent.
--
-- This script performs ZERO writes. It only reports what a real backfill
-- would eventually do to historical `transactions` rows that were enriched
-- before `merchants`/`merchant_locations` existed (they have a resolved
-- `place_google_place_id` but `merchant_id is null`). It is wrapped in
-- `begin; ... rollback;` as a second, belt-and-braces safety net even though
-- every statement below is a plain `select` and none can mutate data.
--
-- Run manually against the target database with any multi-statement-capable
-- psql client. The installed `supabase` CLI's own `db query --file` (v2.108)
-- executes the file as a single prepared statement over the extended query
-- protocol and errors with "cannot insert multiple commands into a prepared
-- statement" on a multi-select file like this one, so do NOT use it here.
-- Verified working alternatives:
--   * Local dev DB, via the `supabase db start` Postgres container's own
--     bundled psql (no local psql install required):
--       Get-Content -Raw supabase/scripts/20260724_merchant_intelligence_backfill_dry_run.sql |
--         docker exec -i supabase_db_<project> psql -U postgres -d postgres -v ON_ERROR_STOP=1
--   * Any environment with a local `psql`, against the local or a
--     linked/remote project:
--       psql "$(supabase status -o env | ...)" -f supabase/scripts/20260724_merchant_intelligence_backfill_dry_run.sql
--   * Paste the body into the Supabase Studio SQL editor (also a
--     multi-statement-capable client).
--
-- Normalization-approximation caveat (read before trusting groupings below):
-- the real brand-comparison key is `normalizeForCompare()` in
-- supabase/functions/_shared/place_matching.ts — lowercase, then collapse
-- every run of non `[a-z0-9]` characters to a single space, then trim. This
-- script approximates that in pure SQL as:
--   btrim(regexp_replace(lower(merchant_normalized), '[^a-z0-9]+', ' ', 'g'))
-- which is the same algorithm expressed in Postgres regex instead of
-- JavaScript regex, so it should match byte-for-byte for plain ASCII
-- merchant text (the overwhelmingly common case for this dataset). It has
-- NOT been verified against every Unicode edge case (e.g. locale-sensitive
-- lower-casing of non-ASCII letters, or characters treated as "word"
-- characters by one regex engine's Unicode tables but not the other's) — see
-- the task hand-off notes for the full caveat. Treat any grouping decision
-- this script suggests as advisory, not authoritative, until a real backfill
-- re-derives it using the actual TypeScript function (e.g. via a one-off
-- Deno/Node pass) rather than this SQL approximation.

begin;

-- A slightly tighter trigram floor than the pg_trgm default (0.3), scoped to
-- this transaction only, to keep section 4's cross-place report focused on
-- genuinely close textual matches rather than every loosely-related pair.
set local pg_trgm.similarity_threshold = 0.45;

-- NOTE: a `with ... as (...)` CTE is only visible to the single statement it
-- prefixes — it does NOT carry over to later semicolon-separated statements
-- in this script. The `candidates` CTE is therefore intentionally repeated
-- verbatim ahead of each section (1-4) below that needs it, rather than
-- defined once, so every section remains one independently runnable
-- statement.

-- ---------------------------------------------------------------------------
-- 1. Backfill candidate volume: total transactions a real backfill would
--    eventually touch (resolved place, not yet linked to a merchant).
-- ---------------------------------------------------------------------------
with candidates as (
  select
    t.id,
    t.place_google_place_id,
    t.merchant_normalized
  from public.transactions t
  where t.place_google_place_id is not null
    and btrim(t.place_google_place_id) <> ''
    and t.merchant_id is null
)
select
  count(*) as backfill_candidate_transaction_count
from candidates;

-- ---------------------------------------------------------------------------
-- 2. Exact-place-ID-first grouping (the SAFE, high-confidence tier). A
--    single `google_place_id` really is one physical location, so grouping
--    by it alone is the tier the plan says to apply first. For each
--    candidate place: how many transactions would attach to it, how many
--    distinct raw `merchant_normalized` strings were seen for that same
--    place, and which one is most common (mode).
-- ---------------------------------------------------------------------------
with candidates as (
  select
    t.id,
    t.place_google_place_id,
    t.merchant_normalized
  from public.transactions t
  where t.place_google_place_id is not null
    and btrim(t.place_google_place_id) <> ''
    and t.merchant_id is null
)
select
  place_google_place_id,
  count(*) as transaction_count,
  count(distinct merchant_normalized) as distinct_raw_merchant_normalized_count,
  mode() within group (order by merchant_normalized) as most_common_merchant_normalized
from candidates
group by place_google_place_id
order by transaction_count desc, place_google_place_id;

-- ---------------------------------------------------------------------------
-- 3. Brand-name inconsistency flag WITHIN the same place (informational
--    only — report for human review, do not resolve). Uses the normalized
--    approximation from the header comment so trivial case/punctuation
--    differences don't inflate the distinct count; only genuinely different
--    normalized brand text for the same physical place is flagged.
-- ---------------------------------------------------------------------------
with candidates as (
  select
    t.id,
    t.place_google_place_id,
    btrim(
      regexp_replace(lower(coalesce(t.merchant_normalized, '')), '[^a-z0-9]+', ' ', 'g')
    ) as merchant_normalized_approx
  from public.transactions t
  where t.place_google_place_id is not null
    and btrim(t.place_google_place_id) <> ''
    and t.merchant_id is null
)
select
  place_google_place_id,
  count(*) as transaction_count,
  count(distinct merchant_normalized_approx) as distinct_normalized_brand_count,
  array_agg(distinct merchant_normalized_approx) as distinct_normalized_brands_seen
from candidates
where merchant_normalized_approx <> ''
group by place_google_place_id
having count(distinct merchant_normalized_approx) > 1
order by transaction_count desc, place_google_place_id;

-- ---------------------------------------------------------------------------
-- 4. Fuzzy cross-place candidate report (the RISKY tier — report only, NEVER
--    auto-apply). Distinct (place, normalized-brand-text) pairs whose
--    normalized text is textually very similar via pg_trgm `similarity()`/`%`
--    but that resolved to *different* Google Place IDs. These are candidate
--    same-brand-different-branch (or, just as plausibly, unrelated
--    same-named-business) pairs that only a separate, human-reviewed pass
--    should ever consider merging — this script does not group or write
--    anything for them.
-- ---------------------------------------------------------------------------
with candidates as (
  select
    t.place_google_place_id,
    btrim(
      regexp_replace(lower(coalesce(t.merchant_normalized, '')), '[^a-z0-9]+', ' ', 'g')
    ) as merchant_normalized_approx
  from public.transactions t
  where t.place_google_place_id is not null
    and btrim(t.place_google_place_id) <> ''
    and t.merchant_id is null
),
distinct_place_brand as (
  select
    place_google_place_id,
    merchant_normalized_approx,
    count(*) as transaction_count
  from candidates
  where merchant_normalized_approx <> ''
  group by place_google_place_id, merchant_normalized_approx
)
select
  a.place_google_place_id as place_id_a,
  a.merchant_normalized_approx as brand_text_a,
  a.transaction_count as transaction_count_a,
  b.place_google_place_id as place_id_b,
  b.merchant_normalized_approx as brand_text_b,
  b.transaction_count as transaction_count_b,
  similarity(a.merchant_normalized_approx, b.merchant_normalized_approx) as trigram_similarity
from distinct_place_brand a
join distinct_place_brand b
  on a.place_google_place_id < b.place_google_place_id
  and a.merchant_normalized_approx % b.merchant_normalized_approx
where a.merchant_normalized_approx <> b.merchant_normalized_approx
order by trigram_similarity desc, place_id_a, place_id_b;

-- ---------------------------------------------------------------------------
-- 5. Current invariant sanity checks (before any backfill ever runs). Every
--    query below is expected to return ZERO rows today — each condition
--    should already be structurally impossible given existing constraints
--    (the unique index on `merchant_locations.google_place_id`, and the FKs
--    from `transactions`/`merchant_locations` to `merchants`/
--    `merchant_locations`). This is a defensive "prove it" check, not a
--    redundant one: it would only ever find rows if something bypassed
--    those constraints (e.g. a service-role write, a constraint dropped and
--    not restored, or a restored backup taken mid-migration).
-- ---------------------------------------------------------------------------

-- 5a. No duplicate merchant_locations.google_place_id values.
select
  google_place_id,
  count(*) as duplicate_count
from public.merchant_locations
group by google_place_id
having count(*) > 1;

-- 5b. No transactions.merchant_id pointing at a nonexistent merchants.id.
select
  t.id as transaction_id,
  t.merchant_id as dangling_merchant_id
from public.transactions t
left join public.merchants m on m.id = t.merchant_id
where t.merchant_id is not null
  and m.id is null;

-- 5c. No transactions.merchant_location_id pointing at a nonexistent
--     merchant_locations.id.
select
  t.id as transaction_id,
  t.merchant_location_id as dangling_merchant_location_id
from public.transactions t
left join public.merchant_locations l on l.id = t.merchant_location_id
where t.merchant_location_id is not null
  and l.id is null;

-- 5d. No merchant_locations row whose merchant_id doesn't exist in
--     merchants.
select
  l.id as merchant_location_id,
  l.merchant_id as dangling_merchant_id
from public.merchant_locations l
left join public.merchants m on m.id = l.merchant_id
where m.id is null;

rollback;
