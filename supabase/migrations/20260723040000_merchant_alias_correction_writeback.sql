-- Second write-back trigger into the existing `merchant_aliases` cache
-- (20260708000000_merchant_aliases.sql): an explicit user correction — a
-- `user_locked` place-picker override, or a free-text merchant-name edit —
-- not only the algorithmic >=0.85-confidence auto-resolve path.
-- See docs/plans/2026-07-23-feedback-learning-system.md.
--
-- Called from `enrich-transaction` (supabase/functions/enrich-transaction/
-- index.ts), which by the time it calls this already has a resolved place
-- (either the transaction's own `user_locked` fields, or its own freshly-
-- resolved Places `winner`) — this function only decides *how much to trust*
-- keying the alias on the user's corrected text, never re-resolves Places
-- itself.
--
-- Trust tiers (Decision Logic):
--   'user_locked' — a deliberate, multi-step picker pick is trusted
--   immediately, same level as today's algorithmic path.
--   'free_text'   — a quick text edit is corroboration-gated whenever it
--   disagrees with an already-established (confidence >= 0.7) entry for the
--   same key: it's written as a low-confidence competing candidate that can
--   only displace the established entry once it has recurred
--   `v_corroboration_threshold` times. This is the feature's primary
--   defense against a single bad free-text edit poisoning a table every
--   user shares.

create or replace function public.upsert_merchant_alias_from_correction(
  p_alias_text text,
  p_geohash text,
  p_place_id text,
  p_name text,
  p_lat double precision,
  p_lng double precision,
  p_correction_type text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_established record;
  v_candidate record;
  v_corroboration_threshold constant integer := 3;
  v_promoted_confidence constant double precision := 0.88;
begin
  if p_correction_type = 'user_locked' then
    perform public.upsert_merchant_alias(
      p_alias_text, p_geohash, p_place_id, p_name, p_lat, p_lng, 0.9
    );
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
    -- No established entry, or this correction agrees with it — write/
    -- reinforce directly, same trust as today's confident auto-resolve path.
    perform public.upsert_merchant_alias(
      p_alias_text, p_geohash, p_place_id, p_name, p_lat, p_lng, 0.75
    );
    return;
  end if;

  -- Disagrees with an established entry: write as a low-weight competing
  -- candidate (a distinct row — merchant_aliases' unique key includes
  -- canonical_place_id — so the established row is never touched here).
  perform public.upsert_merchant_alias(
    p_alias_text, p_geohash, p_place_id, p_name, p_lat, p_lng, 0.2
  );

  select *
  into v_candidate
  from public.merchant_aliases
  where alias_text_normalized = p_alias_text
    and geohash_bucket = p_geohash
    and canonical_place_id = p_place_id;

  if v_candidate.hit_count >= v_corroboration_threshold then
    update public.merchant_aliases
    set confidence = v_promoted_confidence
    where id = v_candidate.id;
  end if;
end;
$$;

revoke execute on function public.upsert_merchant_alias_from_correction(
  text, text, text, text, double precision, double precision, text
) from public;
grant execute on function public.upsert_merchant_alias_from_correction(
  text, text, text, text, double precision, double precision, text
) to authenticated;
