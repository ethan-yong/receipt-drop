begin;

select plan(26);

select has_extension('pg_trgm', 'pg_trgm extension is installed');
select has_table('public', 'merchants', 'merchants table exists');
select has_table(
  'public',
  'merchant_locations',
  'merchant_locations table exists'
);

select ok(
  not exists (
    select 1
    from unnest(array[
      'id', 'canonical_name', 'normalized_name_key', 'vendor_category',
      'typical_place_types', 'observation_count', 'confidence', 'created_at',
      'last_observed_at'
    ]) expected(column_name)
    where not exists (
      select 1
      from information_schema.columns actual
      where actual.table_schema = 'public'
        and actual.table_name = 'merchants'
        and actual.column_name = expected.column_name
    )
  ),
  'merchants has all foundation columns'
);

select ok(
  not exists (
    select 1
    from unnest(array[
      'id', 'merchant_id', 'google_place_id', 'geohash_bucket', 'lat', 'lng',
      'place_name', 'confidence', 'hit_count', 'created_at', 'last_matched_at',
      'spatial_point'
    ]) expected(column_name)
    where not exists (
      select 1
      from information_schema.columns actual
      where actual.table_schema = 'public'
        and actual.table_name = 'merchant_locations'
        and actual.column_name = expected.column_name
    )
  ),
  'merchant_locations has all foundation columns'
);

select ok(
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'merchants'
      and column_name = 'vendor_category'
      and is_nullable = 'YES'
  ),
  'merchants.vendor_category is nullable'
);

select ok(
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'merchants'
      and column_name = 'typical_place_types'
      and data_type = 'ARRAY'
  )
  and exists (
    select 1
    from pg_constraint
    where conrelid = to_regclass('public.merchants')
      and conname = 'merchants_typical_place_types_bounded'
  ),
  'merchant place-type aggregate is an array with a size bound'
);

select ok(
  not exists (
    select 1
    from pg_index index_def
    join pg_attribute column_def
      on column_def.attrelid = index_def.indrelid
     and column_def.attname = 'normalized_name_key'
    where index_def.indrelid = to_regclass('public.merchants')
      and index_def.indisunique
      and index_def.indnkeyatts = 1
      and column_def.attnum = any(index_def.indkey)
  ),
  'merchants.normalized_name_key is not globally unique'
);

select has_index(
  'public',
  'merchants',
  'merchants_normalized_name_trgm_idx',
  'merchant fuzzy lookup has a trigram index'
);

select ok(
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'merchant_locations'
      and column_name = 'google_place_id'
      and is_nullable = 'NO'
  ),
  'merchant_locations.google_place_id is required'
);

select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = to_regclass('public.merchant_locations')
      and conname = 'merchant_locations_google_place_id_key'
      and contype = 'u'
  ),
  'Google place id is globally unique'
);

select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = to_regclass('public.merchant_locations')
      and conname = 'merchant_locations_merchant_id_fkey'
      and confdeltype = 'c'
  ),
  'deleting a merchant cascades to its locations'
);

select ok(
  exists (
    select 1
    from pg_attribute
    where attrelid = to_regclass('public.merchant_locations')
      and attname = 'spatial_point'
      and attgenerated = 's'
      and format_type(atttypid, atttypmod) = 'geography(Point,4326)'
  ),
  'merchant location has a stored geography point'
);

select has_index(
  'public',
  'merchant_locations',
  'merchant_locations_spatial_point_gix',
  'merchant location geography has a GiST index'
);

select ok(
  (
    select relrowsecurity
    from pg_class
    where oid = to_regclass('public.merchants')
  )
  and (
    select relrowsecurity
    from pg_class
    where oid = to_regclass('public.merchant_locations')
  ),
  'RLS is enabled on both global tables'
);

select ok(
  not exists (
    select 1
    from pg_policy
    where polrelid in (
      to_regclass('public.merchants'),
      to_regclass('public.merchant_locations')
    )
  ),
  'global merchant tables have zero RLS policies'
);

select ok(
  not exists (
    select 1
    from information_schema.role_table_grants
    where table_schema = 'public'
      and table_name in ('merchants', 'merchant_locations')
      and grantee in ('anon', 'authenticated', 'PUBLIC')
  ),
  'global merchant tables have no direct client read grants'
);

select ok(
  not exists (
    select 1
    from unnest(array['merchant_id', 'merchant_location_id'])
      expected(column_name)
    where not exists (
      select 1
      from information_schema.columns actual
      where actual.table_schema = 'public'
        and actual.table_name = 'merchant_aliases'
        and actual.column_name = expected.column_name
        and actual.is_nullable = 'YES'
    )
  ),
  'merchant_aliases has nullable merchant foreign-key columns'
);

select ok(
  not exists (
    select 1
    from unnest(array['merchant_id', 'merchant_location_id'])
      expected(column_name)
    where not exists (
      select 1
      from information_schema.columns actual
      where actual.table_schema = 'public'
        and actual.table_name = 'transactions'
        and actual.column_name = expected.column_name
        and actual.is_nullable = 'YES'
    )
  ),
  'transactions has nullable merchant foreign-key columns'
);

select ok(
  (
    select count(*) = 4
    from pg_constraint
    where conname in (
      'merchant_aliases_merchant_id_fkey',
      'merchant_aliases_merchant_location_id_fkey',
      'transactions_merchant_id_fkey',
      'transactions_merchant_location_id_fkey'
    )
      and confdeltype = 'n'
  ),
  'alias and transaction merchant FKs use ON DELETE SET NULL'
);

select ok(
  not exists (
    select 1
    from unnest(array[
      'merchant_aliases_merchant_id_idx',
      'merchant_aliases_merchant_location_id_idx',
      'transactions_merchant_id_idx',
      'transactions_merchant_location_id_idx'
    ]) expected(index_name)
    where to_regclass('public.' || expected.index_name) is null
  ),
  'all new nullable foreign keys are indexed'
);

select ok(
  not exists (
    select 1
    from unnest(array[
      'merchant_resolution_method',
      'merchant_resolution_confidence'
    ]) expected(column_name)
    where not exists (
      select 1
      from information_schema.columns actual
      where actual.table_schema = 'public'
        and actual.table_name = 'transactions'
        and actual.column_name = expected.column_name
        and actual.is_nullable = 'YES'
    )
  ),
  'transaction merchant provenance fields are nullable'
);

select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.transactions'::regclass
      and conname = 'transactions_merchant_resolution_method_check'
  )
  and exists (
    select 1
    from pg_constraint
    where conrelid = 'public.transactions'::regclass
      and conname = 'transactions_merchant_resolution_confidence_check'
  ),
  'transaction merchant provenance fields are constrained'
);

select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = to_regclass('public.merchants')
      and conname = 'merchants_confidence_check'
  )
  and exists (
    select 1
    from pg_constraint
    where conrelid = to_regclass('public.merchant_locations')
      and conname = 'merchant_locations_confidence_check'
  ),
  'merchant confidence values are constrained'
);

select ok(
  not exists (
    select 1
    from unnest(array[
      'canonical_place_id', 'canonical_name', 'canonical_lat', 'canonical_lng'
    ]) expected(column_name)
    where not exists (
      select 1
      from information_schema.columns actual
      where actual.table_schema = 'public'
        and actual.table_name = 'merchant_aliases'
        and actual.column_name = expected.column_name
    )
  ),
  'legacy merchant_alias canonical columns remain intact'
);

select has_index(
  'public',
  'merchant_locations',
  'merchant_locations_geohash_bucket_idx',
  'merchant location geohash lookup is indexed'
);

select * from finish();
rollback;
