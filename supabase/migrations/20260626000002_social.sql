-- Friends, feed, and reactions. Cross-user reads are never granted directly
-- on a table (profiles/transactions stay locked to their owner) — they're
-- funneled through narrow `security definer` functions that return only the
-- specific columns each feature needs.

alter table public.profiles add column if not exists current_mood text;
alter table public.profiles drop constraint if exists profiles_current_mood_check;
alter table public.profiles add constraint profiles_current_mood_check
  check (current_mood is null or current_mood in ('calm', 'active', 'spiky', 'balanced'));

-- friendships
create table if not exists public.friendships (
  id uuid primary key,
  requester_id uuid not null references public.profiles(id) on delete cascade,
  addressee_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'blocked')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  constraint friendships_no_self_request check (requester_id != addressee_id),
  unique (requester_id, addressee_id)
);

create index if not exists friendships_addressee_idx on public.friendships (addressee_id);

alter table public.friendships enable row level security;

create policy "friendships_select_party"
  on public.friendships for select
  using (auth.uid() in (requester_id, addressee_id));

create policy "friendships_insert_as_requester"
  on public.friendships for insert
  with check (requester_id = auth.uid());

-- Only the addressee may accept/decline a pending request; either party may
-- block. Without this asymmetry a requester could flip their own outgoing
-- request to 'accepted' and read the addressee's feed/leaderboard without
-- consent.
create policy "friendships_update_party"
  on public.friendships for update
  using (auth.uid() in (requester_id, addressee_id))
  with check (
    auth.uid() in (requester_id, addressee_id)
    and (status = 'blocked' or auth.uid() = addressee_id)
  );

grant select, insert, update on public.friendships to authenticated;

-- Resolves an email to a profile for the add-by-email flow. Security
-- definer so the client never needs direct access to auth.users.
create or replace function public.find_user_by_email(lookup_email text)
returns table (id uuid, display_name text)
language sql
security definer
set search_path = public
as $$
  select p.id, p.display_name
  from public.profiles p
  join auth.users u on u.id = p.id
  where lower(u.email) = lower(lookup_email)
    and p.id != auth.uid()
  limit 1;
$$;

grant execute on function public.find_user_by_email(text) to authenticated;

-- Joins a friendship row with the other party's public profile fields,
-- since profiles_select_own would otherwise block reading a friend's name.
create or replace function public.list_friendships()
returns table (
  id uuid,
  requester_id uuid,
  addressee_id uuid,
  status text,
  created_at timestamptz,
  other_user_id uuid,
  other_display_name text,
  other_avatar_config jsonb
)
language sql
security definer
set search_path = public
as $$
  select
    f.id,
    f.requester_id,
    f.addressee_id,
    f.status,
    f.created_at,
    case when f.requester_id = auth.uid() then f.addressee_id else f.requester_id end,
    p.display_name,
    p.avatar_config
  from public.friendships f
  join public.profiles p
    on p.id = case when f.requester_id = auth.uid() then f.addressee_id else f.requester_id end
  where auth.uid() in (f.requester_id, f.addressee_id)
  order by f.created_at desc;
$$;

grant execute on function public.list_friendships() to authenticated;

-- feed_posts: system-generated flavor text only (see
-- lib/domain/logic/feed_line_generator.dart) — never the raw amount or
-- merchant name, which is what makes it safe to expose cross-user.
create table if not exists public.feed_posts (
  id uuid primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  transaction_id uuid references public.transactions(id) on delete cascade,
  line text not null,
  created_at timestamptz not null default now()
);

create index if not exists feed_posts_user_created_idx on public.feed_posts (user_id, created_at desc);

alter table public.feed_posts enable row level security;

create policy "feed_posts_select_own"
  on public.feed_posts for select using (user_id = auth.uid());

create policy "feed_posts_insert_own"
  on public.feed_posts for insert with check (user_id = auth.uid());

create policy "feed_posts_delete_own"
  on public.feed_posts for delete using (user_id = auth.uid());

grant select, insert, delete on public.feed_posts to authenticated;

-- feed_reactions: insert-only from the client (unique constraint makes
-- repeat taps idempotent); reads only ever happen aggregated, inside
-- get_friend_feed(), so no select policy is needed.
create table if not exists public.feed_reactions (
  id uuid primary key,
  post_id uuid not null references public.feed_posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('fire', 'laugh', 'eyes')),
  created_at timestamptz not null default now(),
  unique (post_id, user_id, kind)
);

alter table public.feed_reactions enable row level security;

create policy "feed_reactions_insert_own"
  on public.feed_reactions for insert with check (user_id = auth.uid());

grant select, insert on public.feed_reactions to authenticated;

-- Friend feed: only accepted friends' posts, with reaction counts
-- aggregated server-side so feed_reactions never needs a cross-user grant.
create or replace function public.get_friend_feed()
returns table (
  post_id uuid,
  user_id uuid,
  display_name text,
  avatar_config jsonb,
  current_mood text,
  line text,
  created_at timestamptz,
  fire_count bigint,
  laugh_count bigint,
  eyes_count bigint
)
language sql
security definer
set search_path = public
as $$
  select
    fp.id,
    fp.user_id,
    p.display_name,
    p.avatar_config,
    p.current_mood,
    fp.line,
    fp.created_at,
    count(*) filter (where r.kind = 'fire') as fire_count,
    count(*) filter (where r.kind = 'laugh') as laugh_count,
    count(*) filter (where r.kind = 'eyes') as eyes_count
  from public.feed_posts fp
  join public.profiles p on p.id = fp.user_id
  left join public.feed_reactions r on r.post_id = fp.id
  where fp.user_id in (
    select case when f.requester_id = auth.uid() then f.addressee_id else f.requester_id end
    from public.friendships f
    where f.status = 'accepted'
      and auth.uid() in (f.requester_id, f.addressee_id)
  )
  group by fp.id, fp.user_id, p.display_name, p.avatar_config, p.current_mood, fp.line, fp.created_at
  order by fp.created_at desc
  limit 100;
$$;

grant execute on function public.get_friend_feed() to authenticated;
