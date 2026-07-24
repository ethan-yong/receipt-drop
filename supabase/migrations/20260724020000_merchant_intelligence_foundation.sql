-- Merchant-intelligence schema foundation only. Candidate/reconciliation RPCs
-- and Edge Function integration are added by later rollout tasks.
create extension if not exists pg_trgm;

-- Global brand identity. normalized_name_key is intentionally NOT unique:
-- distinct businesses can normalize to the same text, so fuzzy resolution
-- must consider a bounded candidate set and additional signals.
create table public.merchants (
  id uuid primary key default gen_random_uuid(),
  canonical_name text not null
    check (btrim(canonical_name) <> ''),
  normalized_name_key text not null
    check (btrim(normalized_name_key) <> ''),
  vendor_category text,
  typical_place_types text[],
  observation_count integer not null default 1
    check (observation_count >= 1),
  confidence double precision not null default 0.5
    constraint merchants_confidence_check
    check (confidence between 0 and 1),
  created_at timestamptz not null default now(),
  last_observed_at timestamptz not null default now(),
  constraint merchants_typical_place_types_bounded
    check (
      typical_place_types is null
      or (
        cardinality(typical_place_types) <= 32
        and octet_length(array_to_string(typical_place_types, ',')) <= 2048
      )
    ),
  constraint merchants_observation_time_ordered
    check (last_observed_at >= created_at)
);

create index merchants_normalized_name_trgm_idx
  on public.merchants
  using gin (normalized_name_key gin_trgm_ops);

-- A v1 location always represents a concrete Google Place with coordinates.
-- google_place_id is globally unique so concurrent reconciliation cannot
-- create the same physical branch under two merchant identities.
create table public.merchant_locations (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null
    references public.merchants(id) on delete cascade,
  google_place_id text not null
    constraint merchant_locations_google_place_id_not_blank
    check (btrim(google_place_id) <> ''),
  geohash_bucket text not null
    constraint merchant_locations_geohash_bucket_not_blank
    check (btrim(geohash_bucket) <> ''),
  lat double precision not null check (lat between -90 and 90),
  lng double precision not null check (lng between -180 and 180),
  place_name text not null check (btrim(place_name) <> ''),
  confidence double precision not null default 0.5
    constraint merchant_locations_confidence_check
    check (confidence between 0 and 1),
  hit_count integer not null default 1 check (hit_count >= 1),
  created_at timestamptz not null default now(),
  last_matched_at timestamptz not null default now(),
  spatial_point geography(Point, 4326)
    generated always as (
      ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography
    ) stored,
  constraint merchant_locations_google_place_id_key unique (google_place_id),
  constraint merchant_locations_match_time_ordered
    check (last_matched_at >= created_at)
);

create index merchant_locations_merchant_id_idx
  on public.merchant_locations (merchant_id);

create index merchant_locations_geohash_bucket_idx
  on public.merchant_locations (geohash_bucket);

create index merchant_locations_merchant_geohash_idx
  on public.merchant_locations (merchant_id, geohash_bucket);

create index merchant_locations_spatial_point_gix
  on public.merchant_locations using gist (spatial_point);

-- Global aggregate tables are server-only. Later migrations add narrow
-- security-definer RPCs; no table policies or client grants are added here.
alter table public.merchants enable row level security;
alter table public.merchant_locations enable row level security;
revoke all on table public.merchants from anon, authenticated;
revoke all on table public.merchant_locations from anon, authenticated;

-- Preserve the existing alias cache shape and legacy canonical_* columns.
-- Entity deletion only clears the new links; it never deletes learned aliases.
alter table public.merchant_aliases
  add column merchant_id uuid
    references public.merchants(id) on delete set null,
  add column merchant_location_id uuid
    references public.merchant_locations(id) on delete set null;

create index merchant_aliases_merchant_id_idx
  on public.merchant_aliases (merchant_id);

create index merchant_aliases_merchant_location_id_idx
  on public.merchant_aliases (merchant_location_id);

-- Nullable, additive transaction links and provenance preserve compatibility
-- with current clients and all historical rows.
alter table public.transactions
  add column merchant_id uuid
    references public.merchants(id) on delete set null,
  add column merchant_location_id uuid
    references public.merchant_locations(id) on delete set null,
  add column merchant_resolution_method text,
  add column merchant_resolution_confidence double precision,
  add constraint transactions_merchant_resolution_method_check
    check (
      merchant_resolution_method is null
      or merchant_resolution_method in (
        'exact_alias',
        'fuzzy_brand',
        'place_id_reconciled',
        'places_search',
        'user_locked'
      )
    ),
  add constraint transactions_merchant_resolution_confidence_check
    check (
      merchant_resolution_confidence is null
      or merchant_resolution_confidence between 0 and 1
    );

create index transactions_merchant_id_idx
  on public.transactions (merchant_id);

create index transactions_merchant_location_id_idx
  on public.transactions (merchant_location_id);
