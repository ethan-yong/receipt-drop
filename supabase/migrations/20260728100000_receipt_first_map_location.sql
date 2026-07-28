-- Map pins use resolved place_lat/lng only — share_location is kept for
-- enrichment fallback but no longer displayed on the spend map.

alter table public.transactions
  drop column if exists place_geom;

alter table public.transactions
  add column place_geom geometry(Point, 4326)
  generated always as (
    case
      when place_lat is not null and place_lng is not null
      then ST_SetSRID(ST_MakePoint(place_lng, place_lat), 4326)
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
    t.place_lat,
    t.place_lng
  from public.transactions t
  where t.user_id = auth.uid()
    and t.place_geom is not null
    and t.place_geom && ST_MakeEnvelope(min_lng, min_lat, max_lng, max_lat, 4326)
    and t.occurred_at >= start_at
    and t.occurred_at < end_at
    and (
      category is null
      or coalesce(t.category_user, t.category_guess, 'Unclassified') = category
    )
  order by t.occurred_at desc
  limit 2000;
$$;

grant execute on function public.get_map_transactions_in_bounds(
  double precision, double precision, double precision, double precision,
  timestamptz, timestamptz, text
) to authenticated;
