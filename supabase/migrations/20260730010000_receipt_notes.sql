-- Freeform user note, most often attached via the post-share notification's
-- inline reply before the receipt was ever confirmed (see
-- docs/plans/2026-07-30-post-share-receipt-notification.md). Mirrors the
-- Drift-side `outbox_transactions.notes` / `pending_imports.note` columns.
--
-- Owner-scoped like every other transactions column: no new RLS policy
-- needed, it rides the table's existing per-user policies. Same for
-- pending_receipts, which already has an owner-only policy.

alter table public.transactions
  add column if not exists notes text;

alter table public.pending_receipts
  add column if not exists note text;
