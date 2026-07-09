-- Merchant candidate context + a global merchant-alias cache so a garbled
-- OCR merchant name (e.g. "RESTORAN ANWAR MAU") that Places has already
-- resolved once (to "Restoran Anwar Maju") near a given location can be
-- resolved again instantly without another Places call.
--
-- The alias table is deliberately GLOBAL (no user_id), not per-user:
-- merchant/business names aren't sensitive per-user data, and one user's
-- successful resolution should help every user who later scans a receipt
-- from the same place — same reasoning as the public `config` storage
-- bucket. It is NOT exposed to clients directly: like get_friend_feed()
-- and list_leaderboard_scores(), all reads/writes are funneled through
-- narrow security-definer functions so the raw table can stay locked down
-- (no RLS policy grants it to `authenticated`/`anon` at all).

alter table public.transactions
  add column if not exists merchant_candidates jsonb,
  add column if not exists ocr_header_text text;

create table if not exists public.merchant_aliases (
  id uuid primary key default gen_random_uuid(),
  alias_text_normalized text not null,
  geohash_bucket text not null,
  canonical_place_id text not null,
  canonical_name text not null,
  canonical_lat double precision,
  canonical_lng double precision,
  confidence double precision not null check (confidence between 0 and 1),
  hit_count integer not null default 1,
  created_at timestamptz not null default now(),
  last_matched_at timestamptz not null default now(),
  unique (alias_text_normalized, geohash_bucket, canonical_place_id)
);

create index if not exists merchant_aliases_lookup_idx
  on public.merchant_aliases (alias_text_normalized, geohash_bucket);

alter table public.merchant_aliases enable row level security;
-- No policies: this table has no direct client access at all, by design.

create or replace function public.lookup_merchant_alias(
  p_alias_text text,
  p_geohash text
)
returns table (
  place_id text,
  name text,
  lat double precision,
  lng double precision,
  confidence double precision
)
language sql
security definer
set search_path = public
as $$
  select
    canonical_place_id,
    canonical_name,
    canonical_lat,
    canonical_lng,
    confidence
  from public.merchant_aliases
  where alias_text_normalized = p_alias_text
    and geohash_bucket = p_geohash
  order by confidence desc
  limit 1;
$$;

-- Postgres auto-grants EXECUTE to PUBLIC on new functions; revoke it so an
-- unauthenticated (anon-key) caller can't invoke this directly.
revoke execute on function public.lookup_merchant_alias(text, text) from public;
grant execute on function public.lookup_merchant_alias(text, text) to authenticated;

create or replace function public.upsert_merchant_alias(
  p_alias_text text,
  p_geohash text,
  p_place_id text,
  p_name text,
  p_lat double precision,
  p_lng double precision,
  p_confidence double precision
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.merchant_aliases (
    alias_text_normalized, geohash_bucket, canonical_place_id,
    canonical_name, canonical_lat, canonical_lng, confidence
  )
  values (
    p_alias_text, p_geohash, p_place_id,
    p_name, p_lat, p_lng, p_confidence
  )
  on conflict (alias_text_normalized, geohash_bucket, canonical_place_id)
  do update set
    hit_count = merchant_aliases.hit_count + 1,
    confidence = greatest(merchant_aliases.confidence, excluded.confidence),
    canonical_name = excluded.canonical_name,
    canonical_lat = excluded.canonical_lat,
    canonical_lng = excluded.canonical_lng,
    last_matched_at = now();
end;
$$;

-- Same reasoning: an anon caller must not be able to write into the global
-- alias cache directly (it has no auth.uid() check of its own — it's only
-- ever meant to be called by enrich-transaction on behalf of a signed-in
-- user, or, for now, any authenticated caller).
revoke execute on function public.upsert_merchant_alias(
  text, text, text, text, double precision, double precision, double precision
) from public;
grant execute on function public.upsert_merchant_alias(
  text, text, text, text, double precision, double precision, double precision
) to authenticated;
