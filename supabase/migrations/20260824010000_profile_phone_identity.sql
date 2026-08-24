-- Phone-based identity resolution for Bill Split: lets a payer's device
-- contact be recognized as an existing Receipt Drop user (friend or not) by
-- phone number, added as a normal friend_user_id-shaped
-- bill_split_participants row (in-app reminders) instead of an external
-- contact row (WhatsApp reminders).

-- Storage shape matches bill_split_participants.contact_phone exactly: bare
-- digits, country-code-prefixed, no leading '+' — reuses
-- normalizePhoneForWhatsApp()'s existing output verbatim, no second
-- normalization implementation. Not verified — phone_e164 != null means
-- "user-provided," not "confirmed." A future phone_verified_at timestamptz
-- can be added later without redesign.
alter table public.profiles add column if not exists phone_e164 text;

create unique index if not exists profiles_phone_e164_unique_idx
  on public.profiles (phone_e164)
  where phone_e164 is not null;

-- Privacy hardening: profiles_select_accepted_friend lets an accepted
-- friend SELECT a user's entire profile row (RLS is row-level, not
-- column-level). Revoking column-level SELECT from `authenticated` closes
-- that off entirely, including for the owner's own row, while leaving
-- every other profiles column exactly as readable as before (column-level
-- REVOKE composes correctly on top of the existing table-wide grant).
revoke select (phone_e164) on public.profiles from authenticated;

-- Self-read despite the REVOKE above: security definer functions run with
-- the function owner's privileges internally, so this can still read
-- phone_e164 — it just only ever returns the caller's own value. Same
-- pattern as is_username_available()/find_user_by_email().
create or replace function public.get_my_phone_e164()
returns text
language sql
security definer
set search_path = public
as $$
  select phone_e164 from public.profiles where id = auth.uid();
$$;

grant execute on function public.get_my_phone_e164() to authenticated;

-- Batched contact-to-user resolution for the bill-split contact picker.
-- Exact-match only (no LIKE/wildcard), one round trip for every contact's
-- numbers at once. Returns ONLY the four columns needed to render a match
-- badge and add a participant — never any other profiles column.
create or replace function public.find_users_by_phones(lookup_phones text[])
returns table (phone_e164 text, user_id uuid, display_name text, avatar_url text)
language sql
security definer
set search_path = public
as $$
  select p.phone_e164, p.id, p.display_name, p.avatar_url
  from public.profiles p
  where p.phone_e164 = any(lookup_phones)
    and p.id != auth.uid();
$$;

grant execute on function public.find_users_by_phones(text[]) to authenticated;

-- General-purpose narrow profile lookup by known id(s), used by
-- BillSplitRepository to resolve a friend_user_id participant's current
-- display name/avatar even when they aren't an accepted friend (so a
-- phone-matched non-friend shows their real name everywhere a split is
-- viewed, not just right after picking). No friendship check — display_name
-- and avatar_url are already exposed across friend/non-friend boundaries
-- elsewhere in this schema (get_my_split_requests() returns a payer's name/
-- avatar to any participant regardless of friendship), so this introduces
-- no new exposure pattern. Never touches phone_e164.
create or replace function public.get_profile_snippets(lookup_user_ids uuid[])
returns table (id uuid, display_name text, avatar_url text)
language sql
security definer
set search_path = public
as $$
  select p.id, p.display_name, p.avatar_url
  from public.profiles p
  where p.id = any(lookup_user_ids);
$$;

grant execute on function public.get_profile_snippets(uuid[]) to authenticated;
