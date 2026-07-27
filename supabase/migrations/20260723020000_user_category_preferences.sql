-- Per-user (merchant, category) preference signal for the feedback-learning
-- feature (docs/plans/2026-07-23-feedback-learning-system.md). Strictly
-- owner-only — a personal signal, unlike the global merchant-alias cache —
-- so it's a plain RLS-protected table with normal `authenticated`-role
-- functions (SECURITY INVOKER, RLS still applies), not the locked-down
-- zero-policy + SECURITY DEFINER pattern `merchant_aliases` uses.
--
-- `correction_count` is the corroboration gate from Decision Logic: a
-- learned category is only meant to be surfaced/preferred once corrected
-- consistently at least twice for the same (user, merchant) pair — a single
-- correction could be a one-off mistake. When a disagreeing correction
-- arrives, recency wins (the stored category becomes the new one) but the
-- streak resets to 1, since the two most recent corrections no longer agree.

create table if not exists public.user_category_preferences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  merchant_normalized text not null,
  category text not null,
  correction_count integer not null default 1,
  last_corrected_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (user_id, merchant_normalized)
);

create index if not exists user_category_preferences_lookup_idx
  on public.user_category_preferences (user_id, merchant_normalized);

alter table public.user_category_preferences enable row level security;

create policy "user_category_preferences_owner"
  on public.user_category_preferences
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Atomic upsert-with-corroboration-count, callable directly by the owning
-- client (SECURITY INVOKER — the default — so RLS above still applies; this
-- exists only for the atomic increment, not to bypass RLS the way
-- merchant_aliases' SECURITY DEFINER functions do for its global table).
create or replace function public.upsert_category_preference(
  p_merchant_normalized text,
  p_category text
)
returns void
language plpgsql
set search_path = public
as $$
begin
  insert into public.user_category_preferences (
    user_id, merchant_normalized, category, correction_count, last_corrected_at
  )
  values (auth.uid(), p_merchant_normalized, p_category, 1, now())
  on conflict (user_id, merchant_normalized) do update set
    category = excluded.category,
    correction_count = case
      when user_category_preferences.category = excluded.category
        then user_category_preferences.correction_count + 1
      -- Category changed since the last correction: recency wins (Decision
      -- Logic), but the consistency streak restarts.
      else 1
    end,
    last_corrected_at = now();
end;
$$;

revoke execute on function public.upsert_category_preference(text, text)
  from public;
grant execute on function public.upsert_category_preference(text, text)
  to authenticated;

create or replace function public.lookup_category_preference(
  p_merchant_normalized text
)
returns table (category text, correction_count integer)
language sql
set search_path = public
as $$
  select category, correction_count
  from public.user_category_preferences
  where user_id = auth.uid()
    and merchant_normalized = p_merchant_normalized;
$$;

revoke execute on function public.lookup_category_preference(text)
  from public;
grant execute on function public.lookup_category_preference(text)
  to authenticated;
