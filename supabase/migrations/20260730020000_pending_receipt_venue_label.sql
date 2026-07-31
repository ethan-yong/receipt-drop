-- Best-effort nearby-venue name resolved at share time (see
-- docs/plans/2026-07-30-pending-receipt-location-context.md) — a memory
-- aid only. Deliberately no raw lat/lng column here: the coordinate is used
-- transiently to call places-proxy and is never persisted, only the
-- resolved place name is.
--
-- Owner-scoped like pending_receipts' other columns: rides the table's
-- existing owner-only policy, no new RLS needed.

alter table public.pending_receipts
  add column if not exists venue_label text;
