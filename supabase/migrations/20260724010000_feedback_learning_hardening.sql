-- Feedback-learning hardening (docs/plans/2026-07-24-feedback-learning-
-- system-review.md §5 items 1–2 + real weighted confidence):
--   1. Idempotent merchant-alias write-back (dedup by correction row).
--   2. Weighted confidence on write (f(source, ocr_confidence, hit_count)).
--   3. Read-path exponential decay (90-day half-life) on merchant aliases
--      and category preferences.
--   4. Server-side category corroboration gate (correction_count >= 2).

-- ---------------------------------------------------------------------------
-- 1. Idempotency marker on the correction event log
-- ---------------------------------------------------------------------------
alter table public.user_field_corrections
  add column if not exists alias_writeback_applied_at timestamptz;

-- ---------------------------------------------------------------------------
-- 2. Replace upsert_merchant_alias_from_correction with idempotent + weighted
--    signature. CREATE OR REPLACE cannot change argument lists — drop first.
-- ---------------------------------------------------------------------------
drop function if exists public.upsert_merchant_alias_from_correction(
  text, text, text, text, double precision, double precision, text
);

create or replace function public.upsert_merchant_alias_from_correction(
  p_alias_text text,
  p_geohash text,
  p_place_id text,
  p_name text,
  p_lat double precision,
  p_lng double precision,
  p_correction_type text,
  p_transaction_id uuid,
  p_ocr_confidence double precision default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_correction record;
  v_established record;
  v_candidate record;
  v_corroboration_threshold constant integer := 3;
  v_ocr double precision;
  v_base double precision;
  v_weight double precision;
  v_promoted double precision;
begin
  -- Lock the originating correction row so retries/re-enrichment cannot
  -- re-increment hit_count for the same logical correction.
  select id, alias_writeback_applied_at
  into v_correction
  from public.user_field_corrections
  where transaction_id = p_transaction_id
    and field = 'merchant'
    and correction_type = p_correction_type
  order by created_at desc
  limit 1
  for update;

  if v_correction is null then
    return;
  end if;

  if v_correction.alias_writeback_applied_at is not null then
    return;
  end if;

  v_ocr := coalesce(p_ocr_confidence, 0.5);
  -- Clamp OCR into [0, 1] before blending so a bad client payload cannot
  -- push weight outside the intended band via the linear term alone.
  if v_ocr < 0 then
    v_ocr := 0;
  elsif v_ocr > 1 then
    v_ocr := 1;
  end if;

  if p_correction_type = 'user_locked' then
    v_base := 0.90;
    v_weight := greatest(0.05, least(0.97, v_base + 0.15 * (v_ocr - 0.5)));
    perform public.upsert_merchant_alias(
      p_alias_text, p_geohash, p_place_id, p_name, p_lat, p_lng, v_weight
    );
    update public.user_field_corrections
    set alias_writeback_applied_at = now()
    where id = v_correction.id;
    return;
  end if;

  select *
  into v_established
  from public.merchant_aliases
  where alias_text_normalized = p_alias_text
    and geohash_bucket = p_geohash
    and confidence >= 0.7
  order by confidence desc
  limit 1;

  if v_established is null or v_established.canonical_place_id = p_place_id then
    v_base := 0.75;
    v_weight := greatest(0.05, least(0.97, v_base + 0.15 * (v_ocr - 0.5)));
    perform public.upsert_merchant_alias(
      p_alias_text, p_geohash, p_place_id, p_name, p_lat, p_lng, v_weight
    );
    update public.user_field_corrections
    set alias_writeback_applied_at = now()
    where id = v_correction.id;
    return;
  end if;

  -- Disagrees with an established entry: write as a low-weight competing
  -- candidate, then promote once corroboration clears the threshold.
  v_base := 0.20;
  v_weight := greatest(0.05, least(0.97, v_base + 0.15 * (v_ocr - 0.5)));
  perform public.upsert_merchant_alias(
    p_alias_text, p_geohash, p_place_id, p_name, p_lat, p_lng, v_weight
  );

  select *
  into v_candidate
  from public.merchant_aliases
  where alias_text_normalized = p_alias_text
    and geohash_bucket = p_geohash
    and canonical_place_id = p_place_id
  for update;

  if v_candidate.hit_count >= v_corroboration_threshold then
    v_promoted := greatest(
      0.05,
      least(
        0.97,
        0.70 + 0.04 * least(v_candidate.hit_count, 5) + 0.10 * (v_ocr - 0.5)
      )
    );
    update public.merchant_aliases
    set confidence = greatest(confidence, v_promoted)
    where id = v_candidate.id;
  end if;

  update public.user_field_corrections
  set alias_writeback_applied_at = now()
  where id = v_correction.id;
end;
$$;

revoke execute on function public.upsert_merchant_alias_from_correction(
  text, text, text, text, double precision, double precision, text,
  uuid, double precision
) from public;
grant execute on function public.upsert_merchant_alias_from_correction(
  text, text, text, text, double precision, double precision, text,
  uuid, double precision
) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Decayed merchant-alias lookup (90-day half-life on last_matched_at)
-- ---------------------------------------------------------------------------
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
    greatest(
      0.05,
      least(
        0.97,
        confidence * exp(
          -extract(epoch from (now() - last_matched_at)) / 86400.0 / 90.0
        )
      )
    ) as confidence
  from public.merchant_aliases
  where alias_text_normalized = p_alias_text
    and geohash_bucket = p_geohash
  order by
    merchant_aliases.confidence * exp(
      -extract(epoch from (now() - merchant_aliases.last_matched_at))
        / 86400.0 / 90.0
    ) desc
  limit 1;
$$;

-- ---------------------------------------------------------------------------
-- 4. Category preference: corroboration gate + weighted/decayed confidence
-- ---------------------------------------------------------------------------
drop function if exists public.lookup_category_preference(text);

create or replace function public.lookup_category_preference(
  p_merchant_normalized text
)
returns table (
  category text,
  correction_count integer,
  confidence double precision
)
language sql
set search_path = public
as $$
  select
    category,
    correction_count,
    least(
      0.85,
      greatest(
        0.05,
        (0.55 + 0.05 * least(correction_count, 6))
        * exp(
          -extract(epoch from (now() - last_corrected_at)) / 86400.0 / 90.0
        )
      )
    ) as confidence
  from public.user_category_preferences
  where user_id = auth.uid()
    and merchant_normalized = p_merchant_normalized
    and correction_count >= 2;
$$;

revoke execute on function public.lookup_category_preference(text)
  from public;
grant execute on function public.lookup_category_preference(text)
  to authenticated;
