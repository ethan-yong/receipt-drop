-- Tests for the merchant-intelligence reconciliation RPCs added by
-- supabase/migrations/20260724030000_merchant_intelligence_reconciliation.sql:
--   - lookup_merchant_candidates: bounded read-only trigram + alias-evidence
--     candidate retrieval for the pure decision function in
--     supabase/functions/_shared/merchant_resolution.ts.
--   - reconcile_merchant_resolution: atomic, idempotent, transaction-bound
--     write of an already-decided merchant/location resolution.
--
-- Written before the migration exists (TDD) — see
-- supabase/tests/database/merchant_intelligence_schema.test.sql for the
-- foundation-schema tests these extend, and the "Recommended Architecture
-- Approach"/"Risks and Mitigations" sections of the architecture review this
-- task implements against.

begin;

select plan(23);

-- ---------------------------------------------------------------------------
-- Fixtures: two auth users (one "owner", one "attacker") and two
-- transactions owned by the same owner (auth.users only requires `id` to be
-- NOT NULL locally; the on_auth_user_created trigger creates a matching
-- profiles row with a null display_name, which is fine).
-- ---------------------------------------------------------------------------
insert into auth.users (id) values
  ('10000000-0000-0000-0000-00000000000a'),
  ('10000000-0000-0000-0000-00000000000b');

insert into public.transactions (id, user_id) values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-00000000000a'),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-00000000000a');

-- ---------------------------------------------------------------------------
-- Grants: both RPCs are global-catalog-mutating/reading and must only ever
-- be reachable by a signed-in (authenticated-role) caller, never anon/PUBLIC
-- — same convention as lookup_merchant_alias/upsert_merchant_alias.
-- ---------------------------------------------------------------------------
select ok(
  exists (
    select 1
    from information_schema.role_routine_grants
    where routine_schema = 'public'
      and routine_name = 'lookup_merchant_candidates'
      and grantee = 'authenticated'
      and privilege_type = 'EXECUTE'
  )
  and not exists (
    select 1
    from information_schema.role_routine_grants
    where routine_schema = 'public'
      and routine_name = 'lookup_merchant_candidates'
      and grantee in ('anon', 'PUBLIC')
  ),
  'lookup_merchant_candidates is granted to authenticated only'
);

select ok(
  exists (
    select 1
    from information_schema.role_routine_grants
    where routine_schema = 'public'
      and routine_name = 'reconcile_merchant_resolution'
      and grantee = 'authenticated'
      and privilege_type = 'EXECUTE'
  )
  and not exists (
    select 1
    from information_schema.role_routine_grants
    where routine_schema = 'public'
      and routine_name = 'reconcile_merchant_resolution'
      and grantee in ('anon', 'PUBLIC')
  ),
  'reconcile_merchant_resolution is granted to authenticated only'
);

-- ---------------------------------------------------------------------------
-- lookup_merchant_candidates: trigram + alias-evidence retrieval
-- ---------------------------------------------------------------------------
insert into public.merchants (canonical_name, normalized_name_key) values
  ('Restoran Anwar Maju', 'restoran anwar maju'),
  ('Restoran Anwar Maju Jaya', 'restoran anwar maju jaya'),
  ('Totally Unrelated Store', 'totally unrelated store xyz'),
  ('Alias Evidence Cafe', 'zzz completely different brand nomatch');

insert into public.merchant_aliases (
  alias_text_normalized, geohash_bucket, canonical_place_id, canonical_name,
  confidence, merchant_id
)
select
  'restoran anwar maju', 'test_geohash_1', 'place-alias-evidence-1',
  'Alias Evidence Cafe', 0.8, id
from public.merchants
where canonical_name = 'Alias Evidence Cafe';

select ok(
  exists (
    select 1
    from public.lookup_merchant_candidates('restoran anwar maju', 'test_geohash_1', 8)
    where canonical_name = 'Restoran Anwar Maju'
  ),
  'lookup_merchant_candidates surfaces a trigram-similar merchant'
);

select ok(
  exists (
    select 1
    from public.lookup_merchant_candidates('restoran anwar maju', 'test_geohash_1', 8)
    where canonical_name = 'Alias Evidence Cafe'
      and source = 'alias_evidence'
  ),
  'lookup_merchant_candidates surfaces alias-evidence merchant below the similarity floor'
);

select ok(
  not exists (
    select 1
    from public.lookup_merchant_candidates('restoran anwar maju', 'test_geohash_1', 8)
    where canonical_name = 'Totally Unrelated Store'
  ),
  'lookup_merchant_candidates excludes an unrelated merchant'
);

insert into public.merchants (canonical_name, normalized_name_key)
select
  'Kedai Runcit Sinar Chap Test Cabang ' || gs,
  'kedai runcit sinar chap test cabang ' || gs
from generate_series(1, 15) gs;

select ok(
  (
    select count(*)
    from public.lookup_merchant_candidates('kedai runcit sinar chap test cabang', null, 50)
  ) <= 10,
  'lookup_merchant_candidates respects a hard cap even with many matching rows and a larger requested limit'
);

-- ---------------------------------------------------------------------------
-- reconcile_merchant_resolution: ownership must be checked first, inside the
-- same lock — a caller can never mutate a transaction it does not own, no
-- matter what else it passes ("Global catalog poisoning" mitigation).
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-00000000000b', true);
set local role authenticated;

select throws_ok(
  $$select * from public.reconcile_merchant_resolution(
    '20000000-0000-0000-0000-000000000001'::uuid,
    'create_new',
    'place-ownership-check-1',
    'Ownership Check Place',
    3.1,
    101.6,
    'test_geohash_2',
    'places_search',
    0.8,
    null,
    'Ownership Check Brand',
    'ownership check brand',
    null,
    null,
    0.5
  )$$,
  NULL::char(5),
  NULL::text,
  'reconcile_merchant_resolution rejects a transaction not owned by the caller'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------------
-- reconcile_merchant_resolution: input validation (run as the owning user,
-- so these fail on the validation itself, not the ownership check).
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-00000000000a', true);
set local role authenticated;

select throws_ok(
  $$select * from public.reconcile_merchant_resolution(
    '20000000-0000-0000-0000-000000000001'::uuid,
    'create_new',
    'place-blank-name-check',
    'Blank Name Check Place',
    3.1,
    101.6,
    'test_geohash_2',
    'places_search',
    0.8,
    null,
    '   ',
    'blank name check brand',
    null,
    null,
    0.5
  )$$,
  NULL::char(5),
  NULL::text,
  'reconcile_merchant_resolution rejects a blank canonical_name_for_new'
);

select throws_ok(
  $$select * from public.reconcile_merchant_resolution(
    '20000000-0000-0000-0000-000000000001'::uuid,
    'create_new',
    'place-bad-confidence-check',
    'Bad Confidence Check Place',
    3.1,
    101.6,
    'test_geohash_2',
    'places_search',
    1.5,
    null,
    'Bad Confidence Brand',
    'bad confidence brand',
    null,
    null,
    0.5
  )$$,
  NULL::char(5),
  NULL::text,
  'reconcile_merchant_resolution rejects an out-of-range resolution confidence'
);

select throws_ok(
  $$select * from public.reconcile_merchant_resolution(
    '20000000-0000-0000-0000-000000000001'::uuid,
    'create_new',
    'place-huge-types-check',
    'Huge Types Check Place',
    3.1,
    101.6,
    'test_geohash_2',
    'places_search',
    0.8,
    null,
    'Huge Types Brand',
    'huge types brand',
    null,
    (select array_agg('type_' || gs) from generate_series(1, 40) gs),
    0.5
  )$$,
  NULL::char(5),
  NULL::text,
  'reconcile_merchant_resolution rejects an oversized typical_place_types array'
);

select throws_ok(
  $$select * from public.reconcile_merchant_resolution(
    '20000000-0000-0000-0000-000000000001'::uuid,
    'create_new',
    'place-bad-method-check',
    'Bad Method Check Place',
    3.1,
    101.6,
    'test_geohash_2',
    'not_a_real_method',
    0.8,
    null,
    'Bad Method Brand',
    'bad method brand',
    null,
    null,
    0.5
  )$$,
  NULL::char(5),
  NULL::text,
  'reconcile_merchant_resolution rejects an invalid merchant_resolution_method'
);

select throws_ok(
  $$select * from public.reconcile_merchant_resolution(
    '20000000-0000-0000-0000-000000000001'::uuid,
    'attach_existing',
    'place-nonexistent-merchant-check',
    'Nonexistent Merchant Check Place',
    3.1,
    101.6,
    'test_geohash_2',
    'places_search',
    0.8,
    '99999999-9999-9999-9999-999999999999',
    null,
    null,
    null,
    null,
    0.5
  )$$,
  NULL::char(5),
  NULL::text,
  'reconcile_merchant_resolution rejects attaching to a nonexistent merchant_id'
);

-- ---------------------------------------------------------------------------
-- reconcile_merchant_resolution: happy path + idempotent counters + one
-- merchant_locations row per google_place_id across different transactions.
-- ---------------------------------------------------------------------------
select lives_ok(
  $$select * from public.reconcile_merchant_resolution(
    '20000000-0000-0000-0000-000000000001'::uuid,
    'create_new',
    'place-kopi-corner-1',
    'Kopi Corner KLCC',
    3.157,
    101.712,
    'test_geohash_9',
    'places_search',
    0.82,
    null,
    'Kopi Corner Brand',
    'kopi corner brand',
    null,
    null,
    0.6
  )$$,
  'reconcile_merchant_resolution succeeds creating a brand-new merchant + location'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

select ok(
  exists (
    select 1
    from public.transactions t
    join public.merchants m on m.id = t.merchant_id
    join public.merchant_locations l on l.id = t.merchant_location_id
    where t.id = '20000000-0000-0000-0000-000000000001'
      and m.canonical_name = 'Kopi Corner Brand'
      and l.google_place_id = 'place-kopi-corner-1'
      and t.merchant_resolution_method = 'places_search'
      and t.merchant_resolution_confidence = 0.82
  ),
  'reconcile_merchant_resolution persists merchant_id/location_id/method/confidence onto the transaction'
);

select is(
  (select observation_count from public.merchants where canonical_name = 'Kopi Corner Brand'),
  1,
  'a freshly created merchant starts at observation_count = 1 (not double-counted on creation)'
);

select is(
  (select hit_count from public.merchant_locations where google_place_id = 'place-kopi-corner-1'),
  1,
  'a freshly created location starts at hit_count = 1 (not double-counted on creation)'
);

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-00000000000a', true);
set local role authenticated;

select lives_ok(
  $$select * from public.reconcile_merchant_resolution(
    '20000000-0000-0000-0000-000000000001'::uuid,
    'create_new',
    'place-kopi-corner-1',
    'Kopi Corner KLCC',
    3.157,
    101.712,
    'test_geohash_9',
    'places_search',
    0.82,
    null,
    'Kopi Corner Brand',
    'kopi corner brand',
    null,
    null,
    0.6
  )$$,
  'reconcile_merchant_resolution retry for the same transaction+place succeeds (idempotent, not just non-throwing)'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

select is(
  (select observation_count from public.merchants where canonical_name = 'Kopi Corner Brand'),
  1,
  'retrying the same transaction+place does not re-increment merchants.observation_count'
);

select is(
  (select hit_count from public.merchant_locations where google_place_id = 'place-kopi-corner-1'),
  1,
  'retrying the same transaction+place does not re-increment merchant_locations.hit_count'
);

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-00000000000a', true);
set local role authenticated;

-- Note: the merchant id is read from the sibling transaction's own
-- already-persisted `merchant_id` (readable by its owner via the existing
-- `tx_select_own` RLS policy + grant), not by querying `merchants` directly
-- — the `authenticated` role has no grants on `merchants` at all, by design;
-- in real usage the Edge Function would already have this id from
-- `lookup_merchant_candidates`/the earlier RPC's own return value.
select lives_ok(
  $$select * from public.reconcile_merchant_resolution(
    '20000000-0000-0000-0000-000000000002'::uuid,
    'attach_existing',
    'place-kopi-corner-1',
    'Kopi Corner KLCC',
    3.157,
    101.712,
    'test_geohash_9',
    'places_search',
    0.7,
    (select merchant_id from public.transactions where id = '20000000-0000-0000-0000-000000000001'),
    null,
    null,
    null,
    null,
    0.6
  )$$,
  'reconcile_merchant_resolution succeeds reconciling a second, different transaction to the same place'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

select is(
  (select count(*) from public.merchant_locations where google_place_id = 'place-kopi-corner-1')::int,
  1,
  'two different transactions reconciled to the same google_place_id collapse onto one merchant_locations row'
);

select is(
  (select hit_count from public.merchant_locations where google_place_id = 'place-kopi-corner-1'),
  2,
  'a genuinely new (second) transaction assignment to an existing location does increment hit_count'
);

select ok(
  exists (
    select 1
    from public.transactions t1
    join public.transactions t2
      on t1.merchant_id = t2.merchant_id
     and t1.merchant_location_id = t2.merchant_location_id
    where t1.id = '20000000-0000-0000-0000-000000000001'
      and t2.id = '20000000-0000-0000-0000-000000000002'
  ),
  'both transactions reconciled to the same place end up with the same merchant_id/merchant_location_id'
);

select * from finish();
rollback;
