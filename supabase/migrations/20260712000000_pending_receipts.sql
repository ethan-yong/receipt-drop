-- Pending receipts inbox: cloud mirror of the device-local pending_imports
-- Drift table. The device is the immediate source of truth; this table is
-- populated best-effort after the file is saved locally.
create table if not exists public.pending_receipts (
  id uuid primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  -- receipts bucket path: <user_id>/pending/<id>.<ext>
  storage_path text not null,
  file_type text not null,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'completed', 'failed')),
  source_app text,
  -- linked once OCR + save produces a transaction row
  transaction_id uuid references public.transactions(id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.pending_receipts enable row level security;

create policy "pending_receipts_owner"
  on public.pending_receipts
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create index pending_receipts_user_created_idx
  on public.pending_receipts (user_id, created_at desc);
