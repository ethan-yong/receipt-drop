-- Surface the real profile photo (profiles.avatar_url) on Bill Split friend
-- pickers / group chips / split-requests, same reason as
-- 20260804010000_leaderboard_avatar_url.sql and
-- 20260811000000_friend_map_pins_avatar_url.sql. DROP required because
-- Postgres rejects CREATE OR REPLACE when the return type gains a column.

DROP FUNCTION IF EXISTS public.list_friendships();
CREATE FUNCTION public.list_friendships()
RETURNS TABLE (
  id uuid,
  requester_id uuid,
  addressee_id uuid,
  status text,
  created_at timestamptz,
  other_user_id uuid,
  other_display_name text,
  other_avatar_config jsonb,
  other_avatar_url text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    f.id,
    f.requester_id,
    f.addressee_id,
    f.status,
    f.created_at,
    CASE WHEN f.requester_id = auth.uid() THEN f.addressee_id ELSE f.requester_id END,
    p.display_name,
    p.avatar_config,
    p.avatar_url
  FROM public.friendships f
  JOIN public.profiles p
    ON p.id = CASE WHEN f.requester_id = auth.uid() THEN f.addressee_id ELSE f.requester_id END
  WHERE auth.uid() IN (f.requester_id, f.addressee_id)
  ORDER BY f.created_at DESC;
$$;

GRANT EXECUTE ON FUNCTION public.list_friendships() TO authenticated;

DROP FUNCTION IF EXISTS public.list_friend_groups();
CREATE FUNCTION public.list_friend_groups()
RETURNS TABLE (
  group_id uuid,
  name text,
  created_at timestamptz,
  member_user_id uuid,
  member_display_name text,
  member_avatar_config jsonb,
  member_avatar_url text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    g.id,
    g.name,
    g.created_at,
    m.friend_user_id,
    p.display_name,
    p.avatar_config,
    p.avatar_url
  FROM public.friend_groups g
  JOIN public.friend_group_members m ON m.group_id = g.id
  JOIN public.profiles p ON p.id = m.friend_user_id
  WHERE g.owner_id = auth.uid()
  ORDER BY g.created_at DESC, p.display_name;
$$;

GRANT EXECUTE ON FUNCTION public.list_friend_groups() TO authenticated;

DROP FUNCTION IF EXISTS public.get_my_split_requests();
CREATE FUNCTION public.get_my_split_requests()
RETURNS TABLE (
  split_id uuid,
  participant_id uuid,
  transaction_id uuid,
  merchant_raw text,
  payer_user_id uuid,
  payer_display_name text,
  payer_avatar_config jsonb,
  payer_avatar_url text,
  mode text,
  total_myr numeric,
  share_myr numeric,
  paid boolean,
  paid_at timestamptz,
  created_at timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    s.id,
    p.id,
    s.transaction_id,
    t.merchant_raw,
    s.owner_id,
    pr.display_name,
    pr.avatar_config,
    pr.avatar_url,
    s.mode,
    s.total_myr,
    p.share_myr,
    p.paid,
    p.paid_at,
    s.created_at
  FROM public.bill_split_participants p
  JOIN public.bill_splits s ON s.id = p.split_id
  JOIN public.transactions t ON t.id = s.transaction_id
  JOIN public.profiles pr ON pr.id = s.owner_id
  WHERE p.friend_user_id = auth.uid()
  ORDER BY s.created_at DESC;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_split_requests() TO authenticated;
