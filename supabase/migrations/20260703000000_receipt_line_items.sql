-- Receipt Drop: receipt line items (parsed OCR items per transaction)

create table if not exists public.receipt_line_items (
  id uuid primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  transaction_id uuid not null references public.transactions(id) on delete cascade,
  name text not null,
  price_myr numeric(12,2) not null,
  quantity integer,
  confidence double precision,
  sort_order integer not null,
  created_at timestamptz not null default now()
);

create index if not exists receipt_line_items_tx_sort_idx
  on public.receipt_line_items (transaction_id, sort_order);

alter table public.receipt_line_items enable row level security;

create policy "rli_select_own"
  on public.receipt_line_items for select using (user_id = auth.uid());

create policy "rli_insert_own"
  on public.receipt_line_items for insert with check (user_id = auth.uid());

create policy "rli_delete_own"
  on public.receipt_line_items for delete using (user_id = auth.uid());

-- No update policy: line items are immutable once created (mirrors receipt_artifacts).

grant usage on schema public to authenticated;
grant select, insert, update, delete on public.receipt_line_items to authenticated;
