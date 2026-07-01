-- Avatar customization + top-badge ordering on profiles (Impact Drops reframe, Phase 2).
-- Existing profiles_select_own / profiles_update_own RLS policies already cover
-- these new columns on an already-RLS'd table; no new policy needed.

alter table public.profiles
  add column if not exists avatar_config jsonb not null
    default '{"color":"yellow","eyes":"neutral","hat":"cap"}'::jsonb;

alter table public.profiles
  add column if not exists top_badge_order text[] not null default '{}'::text[];

-- User override for the derived impact level shown in the new drop-confirmation UI.
alter table public.transactions
  add column if not exists impact_user text check (impact_user in ('low', 'med', 'high'));
