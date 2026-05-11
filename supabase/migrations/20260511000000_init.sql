-- PuggyBank v1: profiles, transactions, receipt_artifacts + RLS (design spec §6)

-- profiles
create table if not exists public.profiles (
  id uuid primary key references auth.users on delete cascade,
  display_name text,
  avatar_url text,
  wants_friends_beta boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles_select_own"
  on public.profiles for select
  using (id = auth.uid());

create policy "profiles_update_own"
  on public.profiles for update
  using (id = auth.uid());

create policy "profiles_insert_own"
  on public.profiles for insert
  with check (id = auth.uid());

-- transactions
create table if not exists public.transactions (
  id uuid primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  occurred_at timestamptz not null default now(),
  amount_myr numeric(12,2),
  amount_source text check (amount_source in ('ocr','user','blended')),
  needs_amount boolean not null default false,
  merchant_raw text,
  merchant_normalized text,
  category_guess text,
  category_confidence double precision,
  category_user text,
  place_status text not null default 'none'
    check (place_status in ('guess','user_locked','none')),
  place_google_place_id text,
  place_name text,
  place_lat double precision,
  place_lng double precision,
  place_confidence double precision,
  share_location_lat double precision,
  share_location_lng double precision,
  share_location_captured_at timestamptz,
  ocr_confidence double precision,
  pipeline_status text not null default 'provisional'
    check (pipeline_status in ('provisional','enriched','failed_enrichment'))
);

create index if not exists transactions_user_occurred_idx
  on public.transactions (user_id, occurred_at desc);

alter table public.transactions enable row level security;

create policy "tx_select_own"
  on public.transactions for select using (user_id = auth.uid());

create policy "tx_insert_own"
  on public.transactions for insert with check (user_id = auth.uid());

create policy "tx_update_own"
  on public.transactions for update using (user_id = auth.uid());

create policy "tx_delete_own"
  on public.transactions for delete using (user_id = auth.uid());

-- receipt_artifacts
create table if not exists public.receipt_artifacts (
  id uuid primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  transaction_id uuid not null references public.transactions(id) on delete cascade,
  storage_path text not null,
  mime_type text not null,
  created_at timestamptz not null default now()
);

alter table public.receipt_artifacts enable row level security;

create policy "ra_select_own"
  on public.receipt_artifacts for select using (user_id = auth.uid());

create policy "ra_insert_own"
  on public.receipt_artifacts for insert with check (user_id = auth.uid());

create policy "ra_delete_own"
  on public.receipt_artifacts for delete using (user_id = auth.uid());

-- auto-create profile row
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- App clients use the authenticated role; RLS still applies.
grant usage on schema public to authenticated;
grant select, insert, update, delete on public.profiles to authenticated;
grant select, insert, update, delete on public.transactions to authenticated;
grant select, insert, update, delete on public.receipt_artifacts to authenticated;
