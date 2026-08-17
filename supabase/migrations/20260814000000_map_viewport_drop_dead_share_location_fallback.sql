-- The `coalesce(t.place_lat, t.share_location_lat)` / `..._lng` fallback
-- reintroduced in 20260811180000 was dead code: `place_geom` (which gates
-- this function's `where` clause) has been generated from place_lat/place_lng
-- only since 20260728100000 ("Map pins use resolved place_lat/lng only —
-- share_location is kept for enrichment fallback but no longer displayed on
-- the spend map"), so no row reaching the `select` can ever have a null
-- place_lat/place_lng for the fallback to matter. Return the columns
-- directly so the RPC body no longer implies share-location-only receipts
-- can appear on the map. OUT-parameter list is unchanged — CREATE OR REPLACE
-- is enough (no DROP).
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
  lng double precision,
  line_items jsonb,
  receipt_storage_path text
)
language sql
security definer
set search_path = public
as $$
  select
    t.id, t.occurred_at, t.amount_myr, t.category_guess, t.category_user,
    t.merchant_raw, t.place_name, t.place_google_place_id,
    t.place_lat,
    t.place_lng,
    coalesce(li.line_items, '[]'::jsonb),
    ra.storage_path
  from public.transactions t
  left join lateral (
    select jsonb_agg(
      jsonb_build_object(
        'id', rli.id,
        'name', rli.name,
        'price_myr', rli.price_myr,
        'quantity', rli.quantity
      )
      order by rli.sort_order
    ) as line_items
    from public.receipt_line_items rli
    where rli.transaction_id = t.id
  ) li on true
  left join lateral (
    select ra2.storage_path
    from public.receipt_artifacts ra2
    where ra2.transaction_id = t.id
    order by ra2.created_at desc
    limit 1
  ) ra on true
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
  limit 2000;
$$;
