-- Single source-of-truth event log for the feedback-learning-system feature
-- (docs/plans/2026-07-23-feedback-learning-system.md): every predicted-vs-
-- confirmed diff captured on the confirm sheet, before the original value is
-- overwritten. Every other learning surface (merchant-alias write-back,
-- category preference, OCR misread patterns) derives from this table; it
-- never feeds a prediction directly itself.
--
-- Owner-only RLS, matching `transactions`/`pending_receipts` — this is a
-- user's own edit history, not shared cross-user data.

create table if not exists public.user_field_corrections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  transaction_id uuid not null references public.transactions(id) on delete cascade,
  field text not null check (
    field in ('merchant', 'amount', 'category', 'line_item_price')
  ),
  predicted_value text not null,
  confirmed_value text not null,
  -- Merchant text this correction is associated with, regardless of `field`
  -- — always the *predicted* merchant name at capture time. Lets a category
  -- or amount correction still be attributed to a merchant for keying
  -- purposes without re-deriving it downstream.
  merchant_raw text,
  confidence double precision,
  -- For field = 'merchant' only: 'free_text' | 'user_locked'.
  correction_type text,
  -- For field = 'line_item_price' only: which item index changed.
  line_item_index integer,
  created_at timestamptz not null default now()
);

create index if not exists user_field_corrections_user_id_idx
  on public.user_field_corrections (user_id);

create index if not exists user_field_corrections_transaction_id_idx
  on public.user_field_corrections (transaction_id);

alter table public.user_field_corrections enable row level security;

create policy "user_field_corrections_owner"
  on public.user_field_corrections
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
