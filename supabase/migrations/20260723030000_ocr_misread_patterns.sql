-- Anonymized, pattern-only cross-user aggregate for systematic OCR-misread
-- detection (docs/plans/2026-07-23-feedback-learning-system.md). Records
-- only abstracted single-character substitution counts (e.g. "a predicted
-- 'O' was corrected to a confirmed '0'") derived client-side from amount/
-- line-item corrections — the actual digits, amounts, and receipt content
-- never reach this table at all (the abstraction happens before the record
-- is ever constructed; see `lib/domain/logic/misread_pattern_extractor.dart`).
--
-- Global and anonymous by construction, so it uses the same locked-down
-- convention as `merchant_aliases`: zero RLS policies, access only via
-- SECURITY DEFINER functions with EXECUTE explicitly revoked from PUBLIC
-- before being granted to `authenticated` (Postgres auto-grants new
-- functions to PUBLIC — see the warning already on record in
-- memory/bugs.md for merchant_aliases).

create table if not exists public.ocr_misread_patterns (
  id uuid primary key default gen_random_uuid(),
  from_char text not null,
  to_char text not null,
  hit_count integer not null default 1,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  unique (from_char, to_char)
);

create index if not exists ocr_misread_patterns_lookup_idx
  on public.ocr_misread_patterns (from_char, to_char);

alter table public.ocr_misread_patterns enable row level security;
-- No policies: this table has no direct client access at all, by design —
-- mirrors merchant_aliases exactly.

create or replace function public.lookup_misread_patterns()
returns table (from_char text, to_char text, hit_count integer)
language sql
security definer
set search_path = public
as $$
  select from_char, to_char, hit_count
  from public.ocr_misread_patterns
  order by hit_count desc;
$$;

revoke execute on function public.lookup_misread_patterns() from public;
grant execute on function public.lookup_misread_patterns() to authenticated;

create or replace function public.upsert_misread_pattern(
  p_from_char text,
  p_to_char text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.ocr_misread_patterns (from_char, to_char)
  values (p_from_char, p_to_char)
  on conflict (from_char, to_char)
  do update set
    hit_count = ocr_misread_patterns.hit_count + 1,
    last_seen_at = now();
end;
$$;

revoke execute on function public.upsert_misread_pattern(text, text)
  from public;
grant execute on function public.upsert_misread_pattern(text, text)
  to authenticated;
