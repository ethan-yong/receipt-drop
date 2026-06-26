-- Per-user badge progress (catalog itself is bundled client-side, assets/config/badges-v1.json).
create table if not exists public.user_badges (
  id uuid primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  badge_id text not null,
  progress numeric not null default 0,
  earned boolean not null default false,
  earned_at timestamptz,
  updated_at timestamptz not null default now(),
  unique (user_id, badge_id)
);

alter table public.user_badges enable row level security;

create policy "user_badges_select_own"
  on public.user_badges for select using (user_id = auth.uid());

create policy "user_badges_insert_own"
  on public.user_badges for insert with check (user_id = auth.uid());

create policy "user_badges_update_own"
  on public.user_badges for update using (user_id = auth.uid());

grant select, insert, update, delete on public.user_badges to authenticated;
