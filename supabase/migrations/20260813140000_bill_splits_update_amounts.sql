-- Allow the payer to rewrite snapshotted split amounts after editing a
-- receipt (total / line-item prices). Composition (who / mode / item
-- assignments) stays insert-or-delete only — no "edit who is splitting" UI.
-- Participant share_myr already had an owner update policy.

create policy "bill_splits_update_own"
  on public.bill_splits for update
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

grant update on public.bill_splits to authenticated;
