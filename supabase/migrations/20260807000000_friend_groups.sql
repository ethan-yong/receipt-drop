-- Friend groups: named, persisted subsets of a user's accepted friends, for
-- one-tap group selection in the Bill Split flow's "who's splitting" step.
-- Same shape as friendships in 20260626000002_social.sql: owner-only RLS on
-- the base tables, cross-user profile reads funneled through a narrow
-- security definer function rather than a direct grant.

create table if not exists public.friend_groups (
  id uuid primary key,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now()
);

create index if not exists friend_groups_owner_idx on public.friend_groups (owner_id);

alter table public.friend_groups enable row level security;

create policy "friend_groups_select_own"
  on public.friend_groups for select
  using (owner_id = auth.uid());

create policy "friend_groups_insert_own"
  on public.friend_groups for insert
  with check (owner_id = auth.uid());

create policy "friend_groups_update_own"
  on public.friend_groups for update
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy "friend_groups_delete_own"
  on public.friend_groups for delete
  using (owner_id = auth.uid());

grant select, insert, update, delete on public.friend_groups to authenticated;

create table if not exists public.friend_group_members (
  group_id uuid not null references public.friend_groups(id) on delete cascade,
  friend_user_id uuid not null references public.profiles(id) on delete cascade,
  added_at timestamptz not null default now(),
  primary key (group_id, friend_user_id)
);

create index if not exists friend_group_members_group_idx
  on public.friend_group_members (group_id);

alter table public.friend_group_members enable row level security;

create policy "friend_group_members_select_own_group"
  on public.friend_group_members for select
  using (exists (
    select 1 from public.friend_groups g
    where g.id = group_id and g.owner_id = auth.uid()
  ));

-- A member row is only insertable when the group belongs to the caller AND
-- friend_user_id is an accepted friend of the caller — declarative check
-- (no trigger) so a group can never be seeded with a non-friend or a
-- stranger's group can never be added to.
create policy "friend_group_members_insert_own_group"
  on public.friend_group_members for insert
  with check (
    exists (
      select 1 from public.friend_groups g
      where g.id = group_id and g.owner_id = auth.uid()
    )
    and exists (
      select 1 from public.friendships f
      where f.status = 'accepted'
        and (
          (f.requester_id = auth.uid() and f.addressee_id = friend_user_id)
          or (f.addressee_id = auth.uid() and f.requester_id = friend_user_id)
        )
    )
  );

create policy "friend_group_members_delete_own_group"
  on public.friend_group_members for delete
  using (exists (
    select 1 from public.friend_groups g
    where g.id = group_id and g.owner_id = auth.uid()
  ));

grant select, insert, delete on public.friend_group_members to authenticated;

-- Joins group membership with each member's public profile fields, since
-- profiles_select_own would otherwise block reading a friend's name/avatar
-- (mirrors list_friendships() in 20260626000002_social.sql).
create or replace function public.list_friend_groups()
returns table (
  group_id uuid,
  name text,
  created_at timestamptz,
  member_user_id uuid,
  member_display_name text,
  member_avatar_config jsonb
)
language sql
security definer
set search_path = public
as $$
  select g.id, g.name, g.created_at, m.friend_user_id, p.display_name, p.avatar_config
  from public.friend_groups g
  join public.friend_group_members m on m.group_id = g.id
  join public.profiles p on p.id = m.friend_user_id
  where g.owner_id = auth.uid()
  order by g.created_at desc, p.display_name;
$$;

grant execute on function public.list_friend_groups() to authenticated;
