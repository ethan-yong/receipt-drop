-- Fix `profiles_select_accepted_friend` (added 20260630000000_leaderboard_api.sql):
-- its EXISTS subquery wrote a bare `id in (f.requester_id, f.addressee_id)`
-- intending the outer profiles.id, but `friendships` (aliased `f`) has its own
-- `id` primary key column, so Postgres bound the unqualified `id` to `f.id`
-- instead. `f.id in (f.requester_id, f.addressee_id)` is essentially always
-- false (a friendship row's own uuid never equals its requester/addressee),
-- so the policy silently never granted friend visibility — get_friend_leaderboard()
-- (and any other friend-scoped profile read) has only ever returned the
-- caller's own row.

drop policy if exists "profiles_select_accepted_friend" on public.profiles;

create policy "profiles_select_accepted_friend"
  on public.profiles for select
  using (
    id = auth.uid()
    or exists (
      select 1
      from public.friendships f
      where f.status = 'accepted'
        and auth.uid() in (f.requester_id, f.addressee_id)
        and profiles.id in (f.requester_id, f.addressee_id)
    )
  );
