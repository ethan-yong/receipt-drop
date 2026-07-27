-- Cross-table/multi-row invariant tests for the merchant-intelligence layer
-- that complement (and deliberately do not restate) the existing:
--   - supabase/tests/database/merchant_intelligence_schema.test.sql (26
--     assertions: table/column/constraint/index/RLS *shape*).
--   - supabase/tests/database/merchant_intelligence_reconciliation.test.sql
--     (23 assertions: the `lookup_merchant_candidates`/
--     `reconcile_merchant_resolution` RPC behavior).
--
-- This file focuses on invariants that only become meaningful with
-- realistic multi-row data or cross-table relationships that the two files
-- above don't exercise:
--   1. The dry-run backfill report logic in
--      supabase/scripts/20260724_merchant_intelligence_backfill_dry_run.sql
--      (same-place brand-inconsistency flag, and fuzzy cross-place candidate
--      detection) actually finds the cases it's designed to find, and does
--      not flag cases it shouldn't — a behavioral proof of that report's
--      query logic, not just that the underlying tables/columns exist.
--   2. `merchant_locations.google_place_id` global uniqueness is truly
--      enforced by the database for a direct insert under a *different*
--      `merchant_id` (distinct from the schema test's structural "does the
--      unique constraint exist" check).
--   3. Deleting a `merchants` row concretely cascades to its
--      `merchant_locations` rows (`on delete cascade`) but only nulls out
--      (does not delete) any `transactions` that referenced it (`on delete
--      set null`) — verified with real rows, not just by reading the FK
--      constraint definitions.
--   4. The `merchant_locations` lat/lng range CHECK constraints reject an
--      out-of-range direct insert (a behavioral proof distinct from both the
--      schema test's constraint-existence check and the reconciliation
--      RPC's own separate input validation).

begin;

select plan(10);

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
insert into auth.users (id) values
  ('60000000-0000-0000-0000-000000000001');

insert into public.merchants (canonical_name, normalized_name_key) values
  ('Cascade Test Merchant', 'cascade test merchant'),
  ('Dup Test Merchant One', 'dup test merchant one'),
  ('Dup Test Merchant Two', 'dup test merchant two'),
  ('Range Check Merchant', 'range check merchant');

insert into public.merchant_locations (
  merchant_id, google_place_id, geohash_bucket, lat, lng, place_name
)
select id, 'place-cascade-1', 'test_geohash_inv1', 3.1, 101.6, 'Cascade Test Place'
from public.merchants where canonical_name = 'Cascade Test Merchant';

insert into public.merchant_locations (
  merchant_id, google_place_id, geohash_bucket, lat, lng, place_name
)
select id, 'place-dup-test-1', 'test_geohash_inv2', 3.2, 101.7, 'Dup Test Place One'
from public.merchants where canonical_name = 'Dup Test Merchant One';

-- A transaction already reconciled to the "Cascade Test Merchant" location,
-- used by the cascade-delete assertions below.
insert into public.transactions (
  id, user_id, merchant_id, merchant_location_id, place_google_place_id, merchant_normalized
)
select
  '70000000-0000-0000-0000-000000000001',
  '60000000-0000-0000-0000-000000000001',
  m.id,
  l.id,
  'place-cascade-1',
  'Cascade Test Merchant'
from public.merchants m
join public.merchant_locations l on l.merchant_id = m.id
where m.canonical_name = 'Cascade Test Merchant';

-- Historical/unresolved rows (merchant_id left null, as real pre-merchant-
-- intelligence transactions are) feeding the dry-run report logic below:
--   * A deliberately "messy" fuzzy cross-place pair: near-identical
--     normalized brand text resolved to two different Google Place IDs.
--   * An unrelated transaction that must NOT be flagged as similar to them.
--   * A same-place pair with genuinely different brand text (the
--     within-place inconsistency case).
--   * A same-place control pair with identical brand text, proving the
--     within-place check doesn't over-flag a normal, consistent place.
insert into public.transactions (id, user_id, place_google_place_id, merchant_normalized) values
  ('70000000-0000-0000-0000-000000000002', '60000000-0000-0000-0000-000000000001', 'place-inv-branch-a', 'Kopi Kita Kafe'),
  ('70000000-0000-0000-0000-000000000003', '60000000-0000-0000-0000-000000000001', 'place-inv-branch-b', 'Kopi Kita Cafe'),
  ('70000000-0000-0000-0000-000000000004', '60000000-0000-0000-0000-000000000001', 'place-inv-branch-c', 'Totally Different Store'),
  ('70000000-0000-0000-0000-000000000005', '60000000-0000-0000-0000-000000000001', 'place-inv-mixed-1', 'Old Name Sdn Bhd'),
  ('70000000-0000-0000-0000-000000000006', '60000000-0000-0000-0000-000000000001', 'place-inv-mixed-1', 'New Brand Name'),
  ('70000000-0000-0000-0000-000000000007', '60000000-0000-0000-0000-000000000001', 'place-inv-consistent-1', 'Consistent Brand'),
  ('70000000-0000-0000-0000-000000000008', '60000000-0000-0000-0000-000000000001', 'place-inv-consistent-1', 'Consistent Brand');

-- ---------------------------------------------------------------------------
-- 1-2. Fuzzy cross-place candidate detection: mirrors the report query in
-- supabase/scripts/20260724_merchant_intelligence_backfill_dry_run.sql
-- section 4 (same normalization approximation, same similarity floor).
-- ---------------------------------------------------------------------------
set local pg_trgm.similarity_threshold = 0.45;

select ok(
  exists (
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
      select place_google_place_id, merchant_normalized_approx
      from candidates
      where merchant_normalized_approx <> ''
      group by place_google_place_id, merchant_normalized_approx
    )
    select 1
    from distinct_place_brand a
    join distinct_place_brand b
      on a.place_google_place_id < b.place_google_place_id
      and a.merchant_normalized_approx % b.merchant_normalized_approx
    where a.merchant_normalized_approx <> b.merchant_normalized_approx
      and a.place_google_place_id in ('place-inv-branch-a', 'place-inv-branch-b')
      and b.place_google_place_id in ('place-inv-branch-a', 'place-inv-branch-b')
  ),
  'fuzzy cross-place report detects near-identical brand text ("Kopi Kita Kafe"/"Cafe") resolved to two different place IDs'
);

select ok(
  not exists (
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
      select place_google_place_id, merchant_normalized_approx
      from candidates
      where merchant_normalized_approx <> ''
      group by place_google_place_id, merchant_normalized_approx
    )
    select 1
    from distinct_place_brand a
    join distinct_place_brand b
      on a.place_google_place_id < b.place_google_place_id
      and a.merchant_normalized_approx % b.merchant_normalized_approx
    where a.merchant_normalized_approx <> b.merchant_normalized_approx
      and (
        a.place_google_place_id = 'place-inv-branch-c'
        or b.place_google_place_id = 'place-inv-branch-c'
      )
  ),
  'fuzzy cross-place report does not flag an unrelated store ("Totally Different Store") against the messy pair'
);

-- ---------------------------------------------------------------------------
-- 3-4. Same-place brand-inconsistency flag: mirrors the dry-run script's
-- section 3 query.
-- ---------------------------------------------------------------------------
select ok(
  exists (
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
    )
    select 1
    from candidates
    where merchant_normalized_approx <> ''
      and place_google_place_id = 'place-inv-mixed-1'
    group by place_google_place_id
    having count(distinct merchant_normalized_approx) > 1
  ),
  'same-place brand-inconsistency flag detects two different normalized brand names ("Old Name Sdn Bhd"/"New Brand Name") at one place ID'
);

select ok(
  not exists (
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
    )
    select 1
    from candidates
    where merchant_normalized_approx <> ''
      and place_google_place_id = 'place-inv-consistent-1'
    group by place_google_place_id
    having count(distinct merchant_normalized_approx) > 1
  ),
  'same-place brand-inconsistency flag does not fire for a place with consistently-named transactions'
);

-- ---------------------------------------------------------------------------
-- 5. merchant_locations.google_place_id global uniqueness is truly enforced
--    by the database, not merely declared: a direct insert under a
--    *different* merchant_id for an already-used place id must fail.
-- ---------------------------------------------------------------------------
select throws_ok(
  $$
    insert into public.merchant_locations (
      merchant_id, google_place_id, geohash_bucket, lat, lng, place_name
    )
    select id, 'place-dup-test-1', 'test_geohash_inv3', 3.3, 101.8, 'Dup Test Place Two'
    from public.merchants where canonical_name = 'Dup Test Merchant Two'
  $$,
  NULL::char(5),
  NULL::text,
  'a direct insert reusing an existing google_place_id under a different merchant_id violates the unique constraint'
);

-- ---------------------------------------------------------------------------
-- 6. merchant_locations lat/lng CHECK constraints reject a direct
--    out-of-range insert (behavioral proof, not just constraint existence).
-- ---------------------------------------------------------------------------
select throws_ok(
  $$
    insert into public.merchant_locations (
      merchant_id, google_place_id, geohash_bucket, lat, lng, place_name
    )
    select id, 'place-range-check-1', 'test_geohash_inv4', 999, 101.6, 'Range Check Place'
    from public.merchants where canonical_name = 'Range Check Merchant'
  $$,
  NULL::char(5),
  NULL::text,
  'a direct insert with an out-of-range latitude violates the lat CHECK constraint'
);

-- ---------------------------------------------------------------------------
-- 7-10. Deleting a merchants row cascades to its merchant_locations rows
-- but only nulls out (never deletes) a transaction that referenced it.
-- ---------------------------------------------------------------------------
delete from public.merchants where canonical_name = 'Cascade Test Merchant';

select ok(
  not exists (
    select 1 from public.merchant_locations where google_place_id = 'place-cascade-1'
  ),
  'deleting a merchants row cascades to delete its merchant_locations row'
);

select ok(
  exists (
    select 1 from public.transactions
    where id = '70000000-0000-0000-0000-000000000001'
  ),
  'the transaction that referenced the deleted merchant is not itself deleted'
);

select is(
  (select merchant_id from public.transactions where id = '70000000-0000-0000-0000-000000000001'),
  null::uuid,
  'the surviving transaction has merchant_id set to null after its merchant is deleted'
);

select is(
  (select merchant_location_id from public.transactions where id = '70000000-0000-0000-0000-000000000001'),
  null::uuid,
  'the surviving transaction has merchant_location_id set to null after its merchant/location is deleted'
);

select * from finish();
rollback;
