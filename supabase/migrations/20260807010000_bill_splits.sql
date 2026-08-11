-- Bill Split: a receipt's payer creates a split (equal or by line item)
-- with a subset of their friends, tracks who has paid, and can send a
-- best-effort reminder (no push-notification delivery exists in this app —
-- "remind" only stamps a timestamp; discovery is via the friend's own
-- Split Requests screen/Home banner, driven by get_my_split_requests()
-- below). Friends can see and self-report their own share as paid; the
-- payer can also override any participant's paid status.

create table if not exists public.bill_splits (
  id uuid primary key,
  transaction_id uuid not null references public.transactions(id) on delete cascade,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  mode text not null check (mode in ('equal', 'by_item')),
  -- Snapshotted at creation time (not re-derived from transactions.amount_myr)
  -- so a later edit to the receipt's amount can't silently invalidate
  -- already-collected/paid participant shares.
  total_myr numeric(12,2) not null,
  created_at timestamptz not null default now(),
  -- One split per receipt in v1 — "editing" a split means delete + recreate,
  -- there is no in-place edit UI.
  unique (transaction_id)
);

create index if not exists bill_splits_owner_idx on public.bill_splits (owner_id);

alter table public.bill_splits enable row level security;

create policy "bill_splits_select_own"
  on public.bill_splits for select
  using (owner_id = auth.uid());

create policy "bill_splits_insert_own"
  on public.bill_splits for insert
  with check (owner_id = auth.uid());

create policy "bill_splits_delete_own"
  on public.bill_splits for delete
  using (owner_id = auth.uid());

-- No update policy: like receipt_line_items, a split header is immutable
-- once created.

grant select, insert, delete on public.bill_splits to authenticated;

create table if not exists public.bill_split_participants (
  id uuid primary key,
  split_id uuid not null references public.bill_splits(id) on delete cascade,
  friend_user_id uuid not null references public.profiles(id) on delete cascade,
  share_myr numeric(12,2) not null,
  paid boolean not null default false,
  paid_at timestamptz,
  last_reminded_at timestamptz,
  created_at timestamptz not null default now(),
  unique (split_id, friend_user_id)
);

create index if not exists bill_split_participants_split_idx
  on public.bill_split_participants (split_id);

create index if not exists bill_split_participants_friend_idx
  on public.bill_split_participants (friend_user_id);

alter table public.bill_split_participants enable row level security;

create policy "bsp_select_own_split"
  on public.bill_split_participants for select
  using (exists (
    select 1 from public.bill_splits s
    where s.id = split_id and s.owner_id = auth.uid()
  ));

-- A participant may also read their own row directly (not just via the
-- get_my_split_requests() RPC) — needed so the friend-side self-update
-- below has something to read back after writing.
create policy "bsp_select_own_participant"
  on public.bill_split_participants for select
  using (friend_user_id = auth.uid());

create policy "bsp_insert_own_split"
  on public.bill_split_participants for insert
  with check (exists (
    select 1 from public.bill_splits s
    where s.id = split_id and s.owner_id = auth.uid()
  ));

-- Two separate permissive update policies (Postgres OR's them): the payer
-- can update any participant row under their own split; a participant can
-- also update their own row, for self-reporting "I've paid". Column-level
-- restriction isn't enforced here (no precedent for it anywhere else in
-- this schema either) — the friend-side client codepath only ever sends
-- {paid, paid_at}.
create policy "bsp_update_own_split"
  on public.bill_split_participants for update
  using (exists (
    select 1 from public.bill_splits s
    where s.id = split_id and s.owner_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.bill_splits s
    where s.id = split_id and s.owner_id = auth.uid()
  ));

create policy "bsp_update_own_participant"
  on public.bill_split_participants for update
  using (friend_user_id = auth.uid())
  with check (friend_user_id = auth.uid());

create policy "bsp_delete_own_split"
  on public.bill_split_participants for delete
  using (exists (
    select 1 from public.bill_splits s
    where s.id = split_id and s.owner_id = auth.uid()
  ));

grant select, insert, update, delete on public.bill_split_participants to authenticated;

-- Only populated when mode = 'by_item'. Write-once alongside split creation
-- in v1 (no per-item editing UI); kept so a split's item composition can be
-- reconstructed later even though it's never re-read into the UI today.
create table if not exists public.bill_split_item_assignments (
  id uuid primary key,
  split_id uuid not null references public.bill_splits(id) on delete cascade,
  line_item_id uuid not null references public.receipt_line_items(id) on delete cascade,
  assigned_user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (split_id, line_item_id, assigned_user_id)
);

create index if not exists bsia_split_idx on public.bill_split_item_assignments (split_id);
create index if not exists bsia_line_item_idx on public.bill_split_item_assignments (line_item_id);

alter table public.bill_split_item_assignments enable row level security;

create policy "bsia_select_own_split"
  on public.bill_split_item_assignments for select
  using (exists (
    select 1 from public.bill_splits s
    where s.id = split_id and s.owner_id = auth.uid()
  ));

create policy "bsia_insert_own_split"
  on public.bill_split_item_assignments for insert
  with check (exists (
    select 1 from public.bill_splits s
    where s.id = split_id and s.owner_id = auth.uid()
  ));

create policy "bsia_delete_own_split"
  on public.bill_split_item_assignments for delete
  using (exists (
    select 1 from public.bill_splits s
    where s.id = split_id and s.owner_id = auth.uid()
  ));

grant select, insert, delete on public.bill_split_item_assignments to authenticated;

-- A friend's view of every split they're a participant in. transactions and
-- profiles are otherwise owner-only-readable, so this cross-user join has
-- to go through a security definer function (same reasoning as
-- get_friend_feed()/list_friendships() in 20260626000002_social.sql).
create or replace function public.get_my_split_requests()
returns table (
  split_id uuid,
  participant_id uuid,
  transaction_id uuid,
  merchant_raw text,
  payer_user_id uuid,
  payer_display_name text,
  payer_avatar_config jsonb,
  mode text,
  total_myr numeric,
  share_myr numeric,
  paid boolean,
  paid_at timestamptz,
  created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select
    s.id,
    p.id,
    s.transaction_id,
    t.merchant_raw,
    s.owner_id,
    pr.display_name,
    pr.avatar_config,
    s.mode,
    s.total_myr,
    p.share_myr,
    p.paid,
    p.paid_at,
    s.created_at
  from public.bill_split_participants p
  join public.bill_splits s on s.id = p.split_id
  join public.transactions t on t.id = s.transaction_id
  join public.profiles pr on pr.id = s.owner_id
  where p.friend_user_id = auth.uid()
  order by s.created_at desc;
$$;

grant execute on function public.get_my_split_requests() to authenticated;
