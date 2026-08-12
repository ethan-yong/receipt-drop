-- Extends the spend-map viewport RPC with per-receipt detail (line items +
-- receipt photo storage path) so the new Receipt Map Sheet can render items
-- and a photo for any pin regardless of which device captured the receipt —
-- today the viewport rows carry only summary fields, so the map's pin-detail
-- UI has always silently shown "No items scanned" / no photo for most pins.
--
-- `create or replace function` cannot change a function's OUT-parameter list
-- (adding return columns counts as changing the return type), so the
-- original signature is dropped first.
drop function if exists public.get_map_transactions_in_bounds(
  double precision, double precision, double precision, double precision,
  timestamptz, timestamptz, text
);

create function public.get_map_transactions_in_bounds(
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
    coalesce(t.place_lat, t.share_location_lat),
    coalesce(t.place_lng, t.share_location_lng),
    coalesce(li.line_items, '[]'::jsonb),
    ra.storage_path
  from public.transactions t
  left join lateral (
    select jsonb_agg(
      jsonb_build_object(
        'name', rli.name, 'price_myr', rli.price_myr, 'quantity', rli.quantity
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
  limit 2000;  -- explicit cap; the local-only version had no bound at all
$$;

grant execute on function public.get_map_transactions_in_bounds(
  double precision, double precision, double precision, double precision,
  timestamptz, timestamptz, text
) to authenticated;
