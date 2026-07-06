-- Snap-map style friend pins. Same privacy funnel as get_friend_feed:
-- cross-user reads only ever go through a narrow security-definer RPC.
-- Pins expose place + time to accepted friends — NEVER amounts — limited
-- to each friend's single most recent geolocated receipt in the last 30
-- days, and only while their share_map_location toggle is on.

alter table public.profiles
  add column if not exists share_map_location boolean not null default true;

create or replace function public.get_friend_map_pins()
returns table (
  user_id uuid,
  display_name text,
  avatar_config jsonb,
  current_mood text,
  place_name text,
  lat double precision,
  lng double precision,
  occurred_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select distinct on (t.user_id)
    t.user_id,
    p.display_name,
    p.avatar_config,
    p.current_mood,
    t.place_name,
    coalesce(t.place_lat, t.share_location_lat),
    coalesce(t.place_lng, t.share_location_lng),
    t.occurred_at
  from public.transactions t
  join public.profiles p on p.id = t.user_id
  where coalesce(t.place_lat, t.share_location_lat) is not null
    and coalesce(t.place_lng, t.share_location_lng) is not null
    and t.occurred_at > now() - interval '30 days'
    and p.share_map_location
    and t.user_id in (
      select case when f.requester_id = auth.uid() then f.addressee_id else f.requester_id end
      from public.friendships f
      where f.status = 'accepted'
        and auth.uid() in (f.requester_id, f.addressee_id)
    )
  order by t.user_id, t.occurred_at desc;
$$;

grant execute on function public.get_friend_map_pins() to authenticated;
