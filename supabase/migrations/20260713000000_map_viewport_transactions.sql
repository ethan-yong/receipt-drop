-- Spend map viewport query: lets the client fetch only the transactions
-- inside the currently-visible map bounds instead of streaming every local
-- transaction into client-side clustering on each camera move.
create extension if not exists postgis;

-- geometry (not geography) is the right choice here: this is a pure
-- bounding-box viewport query via && + GIST, not a great-circle radius
-- search (unlike merchant_aliases' geohash-bucket matching) — geometry
-- avoids geography<->geometry casting friction for ST_MakeEnvelope.
alter table public.transactions
  add column if not exists place_geom geometry(Point, 4326)
  generated always as (
    case
      when coalesce(place_lat, share_location_lat) is not null
       and coalesce(place_lng, share_location_lng) is not null
      then ST_SetSRID(ST_MakePoint(
             coalesce(place_lng, share_location_lng),
             coalesce(place_lat, share_location_lat)
           ), 4326)
      else null
    end
  ) stored;

create index if not exists transactions_place_geom_gix
  on public.transactions using gist (place_geom);

create or replace function public.get_map_transactions_in_bounds(
  min_lat double precision,
  min_lng double precision,
  max_lat double precision,
  max_lng double precision,
  start_at timestamptz,
  end_at timestamptz,
  category text default null
)
returns table (
  id uuid,
  occurred_at timestamptz,
  amount_myr numeric,
  category_guess text,
  category_user text,
  merchant_raw text,
  place_name text,
  place_google_place_id text,
  lat double precision,
  lng double precision
)
language sql
security definer
set search_path = public
as $$
  select
    t.id, t.occurred_at, t.amount_myr, t.category_guess, t.category_user,
    t.merchant_raw, t.place_name, t.place_google_place_id,
    coalesce(t.place_lat, t.share_location_lat),
    coalesce(t.place_lng, t.share_location_lng)
  from public.transactions t
  where t.user_id = auth.uid()  -- explicit: security definer bypasses RLS
    and t.place_geom is not null
    and t.place_geom && ST_MakeEnvelope(min_lng, min_lat, max_lng, max_lat, 4326)
    and t.occurred_at >= start_at
    and t.occurred_at < end_at
    and (
      category is null
      or coalesce(t.category_user, t.category_guess, 'Unclassified') = category
    )
  order by t.occurred_at desc
  limit 2000;  -- explicit cap; the local-only version had no bound at all
$$;

grant execute on function public.get_map_transactions_in_bounds(
  double precision, double precision, double precision, double precision,
  timestamptz, timestamptz, text
) to authenticated;
