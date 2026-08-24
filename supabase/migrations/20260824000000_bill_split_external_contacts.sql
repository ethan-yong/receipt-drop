-- Bill Split: allow a participant to be an external phone contact with no
-- Receipt Drop account (picked from the payer's device contacts), not just
-- an existing friend. See docs/system/decisions.md and
-- lib/domain/models/bill_split.dart for the client-side shape.

-- A row now represents either a friend (friend_user_id -> profiles,
-- unchanged) or an external contact (contact_name + contact_phone, no
-- profiles row at all). Exactly one shape per row.
alter table public.bill_split_participants
  alter column friend_user_id drop not null,
  add column contact_name text,
  add column contact_phone text; -- normalized digits, wa.me-ready, no leading '+'

alter table public.bill_split_participants
  add constraint bsp_identity_pair_check
  check (
    (friend_user_id is not null and contact_name is null and contact_phone is null)
    or
    (friend_user_id is null and contact_name is not null and contact_phone is not null)
  );

-- unique(split_id, friend_user_id) from 20260807010000_bill_splits.sql is
-- unchanged and still correct: Postgres never treats two NULLs as equal, so
-- multiple external-contact rows (all NULL friend_user_id) don't collide
-- with it or each other.
--
-- No RLS changes needed on bill_split_participants: bsp_select_own_split /
-- bsp_insert_own_split / bsp_update_own_split / bsp_delete_own_split all
-- gate purely on `exists (select 1 from bill_splits s where s.id = split_id
-- and s.owner_id = auth.uid())`, which covers external-contact rows
-- identically to friend rows. bsp_select_own_participant /
-- bsp_update_own_participant (friend self-report of "I've paid") key on
-- `friend_user_id = auth.uid()`, which simply never matches a row with
-- friend_user_id null — correct, since an external contact has no account
-- to log in and self-report with.

-- bill_split_item_assignments: keep assigned_user_id (profiles.id) exactly
-- as-is — it's still used for the owner and for friend assignees. Add a
-- second nullable column pointing at the external contact's own
-- bill_split_participants row. (We can't repoint the FK at
-- bill_split_participants.id everywhere instead, because the owner is a
-- valid assignee with no participants row at all.)
alter table public.bill_split_item_assignments
  alter column assigned_user_id drop not null,
  add column assigned_participant_id uuid references public.bill_split_participants(id) on delete cascade;

alter table public.bill_split_item_assignments
  add constraint bsia_assignee_pair_check
  check (
    (assigned_user_id is not null and assigned_participant_id is null)
    or
    (assigned_user_id is null and assigned_participant_id is not null)
  );

-- The existing unique(split_id, line_item_id, assigned_user_id) stays for
-- profile-keyed rows (nulls in assigned_user_id aren't deduped by it). Add a
-- partial unique index for the participant-keyed (external contact) case.
create unique index if not exists bsia_unique_participant_assignment
  on public.bill_split_item_assignments (split_id, line_item_id, assigned_participant_id)
  where assigned_participant_id is not null;

-- No RLS changes needed here either: bsia_select_own_split /
-- bsia_insert_own_split / bsia_delete_own_split all gate on
-- bill_splits.owner_id = auth.uid() via EXISTS, independent of which
-- assignee column is populated.

-- get_my_split_requests() (20260807010000_bill_splits.sql) needs no change:
-- it joins on `p.friend_user_id = auth.uid()`, which naturally excludes
-- external-contact rows — exactly the desired behavior, since they have no
-- account to see a Split Requests screen with.
