-- Merchant-intelligence reconciliation RPCs (see docs/plans/2026-07-24-
-- merchant-intelligence-layer.md and the accompanying architecture review).
-- These are the only two ways anything is ever read from or written to the
-- global `merchants`/`merchant_locations` tables added by
-- 20260724020000_merchant_intelligence_foundation.sql — both tables have RLS
-- enabled with zero policies and no client grants, same pattern as
-- `merchant_aliases`.
--
-- Edge Function wiring (calling `decideMerchantResolution()` from
-- supabase/functions/_shared/merchant_resolution.ts and then this RPC) is a
-- separate, later "shadow-integration" task. This migration only adds the
-- SQL-side read/write primitives that task will call.

-- ---------------------------------------------------------------------------
-- 1. lookup_merchant_candidates: bounded, read-only candidate retrieval.
--
-- Two signal sources, merged and capped:
--   a. pg_trgm similarity of `normalized_name_key` against the caller's
--      already-normalized brand text, via the existing
--      `merchants_normalized_name_trgm_idx` GIN index (the `%` operator).
--   b. Established `merchant_aliases` evidence for the *exact* same
--      normalized text + geohash bucket that is already linked to a
--      merchant (`merchant_aliases.merchant_id is not null`) — this is real
--      evidence a prior resolution already happened for this exact
--      text+location, so it is surfaced even if it wouldn't otherwise clear
--      the trigram similarity floor (e.g. a heavily abbreviated/garbled OCR
--      string that a human/algorithm has already resolved once before).
--
-- Purely additive/read-only global-catalog data — same trust level as
-- `lookup_merchant_alias` — so it is granted to `authenticated` the same way.
-- ---------------------------------------------------------------------------
create or replace function public.lookup_merchant_candidates(
  p_normalized_text text,
  p_geohash text default null,
  p_limit integer default 8
)
returns table (
  merchant_id uuid,
  canonical_name text,
  typical_place_types text[],
  score double precision,
  source text
)
language sql
stable
security definer
set search_path = public
as $$
  with capped as (
    select least(greatest(coalesce(p_limit, 8), 1), 10) as n
  ),
  trigram_matches as (
    select
      m.id as merchant_id,
      m.canonical_name,
      m.typical_place_types,
      similarity(m.normalized_name_key, p_normalized_text) as score,
      'trigram_similarity'::text as source
    from public.merchants m, capped
    where p_normalized_text is not null
      and btrim(p_normalized_text) <> ''
      and m.normalized_name_key % p_normalized_text
    order by score desc
    limit (select n from capped)
  ),
  alias_matches as (
    select
      m.id as merchant_id,
      m.canonical_name,
      m.typical_place_types,
      1.0::double precision as score,
      'alias_evidence'::text as source
    from public.merchant_aliases a
    join public.merchants m on m.id = a.merchant_id
    where a.merchant_id is not null
      and p_normalized_text is not null
      and a.alias_text_normalized = p_normalized_text
      and p_geohash is not null
      and a.geohash_bucket = p_geohash
  ),
  combined as (
    select * from alias_matches
    union all
    select * from trigram_matches
  ),
  deduped as (
    select distinct on (merchant_id)
      merchant_id, canonical_name, typical_place_types, score, source
    from combined
    order by merchant_id, (source = 'alias_evidence') desc, score desc
  )
  select merchant_id, canonical_name, typical_place_types, score, source
  from deduped
  order by (source = 'alias_evidence') desc, score desc
  limit (select n from capped);
$$;

revoke execute on function public.lookup_merchant_candidates(text, text, integer)
  from public;
grant execute on function public.lookup_merchant_candidates(text, text, integer)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 2. reconcile_merchant_resolution: atomic, idempotent, transaction-bound
--    write of an already-decided resolution (the decision itself comes from
--    the pure `decideMerchantResolution()` TypeScript function — this RPC
--    does not redo that scoring, it only enforces invariants and persists
--    the outcome).
--
-- Invariants enforced here (see the architecture review's "Risks and
-- Mitigations"):
--   - Ownership first, under a row lock: only ever mutates a `transactions`
--     row owned by the calling `auth.uid()`. No matching owned row -> raise.
--     This is what makes it safe to grant EXECUTE to `authenticated`
--     ("Global catalog poisoning" mitigation).
--   - Place-ID-first, race-safe location reconciliation: `google_place_id`
--     is globally unique. A `pg_advisory_xact_lock` keyed on the place id
--     serializes concurrent reconciliations for the *same* place for the
--     duration of this transaction, so the existence check and the eventual
--     insert can never race each other into creating two locations (or two
--     merchants) for one physical place ("Popular-merchant row contention"
--     / avoiding check-then-insert). An `insert ... on conflict
--     (google_place_id) do update` is kept as a second, defense-in-depth
--     layer that collapses to one row even if that lock were ever bypassed
--     — and, either way, never reassigns `merchant_id` on conflict, so an
--     already-resolved location is authoritative and never silently
--     re-parented.
--   - Idempotent counters: `merchants.observation_count` and
--     `merchant_locations.hit_count` only increment when this call is a
--     genuinely new assignment *for this transaction* (compared against
--     what is already persisted on the transactions row before this call
--     mutates anything), and never when the merchant/location row was just
--     freshly created by this same call (its default already represents
--     that first observation). Retrying the same transaction with the same
--     outcome, or re-enrichment, cannot inflate either counter
--     ("Retry-driven counter inflation" mitigation, extending
--     20260724010000_feedback_learning_hardening.sql's correction
--     write-back idempotency to this algorithmic write path).
--   - All caller-controlled inputs are validated in SQL (resolution method,
--     confidences, place fields, new-merchant fields) rather than relying
--     solely on table CHECK constraints, though those remain the backstop.
-- ---------------------------------------------------------------------------
create or replace function public.reconcile_merchant_resolution(
  p_transaction_id uuid,
  p_action text,
  p_google_place_id text,
  p_place_name text,
  p_lat double precision,
  p_lng double precision,
  p_geohash text,
  p_resolution_method text,
  p_resolution_confidence double precision,
  p_merchant_id uuid default null,
  p_canonical_name_for_new text default null,
  p_normalized_name_key_for_new text default null,
  p_vendor_category text default null,
  p_typical_place_types text[] default null,
  p_location_confidence double precision default 0.5
)
returns table (
  merchant_id uuid,
  merchant_location_id uuid
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tx record;
  v_existing_location record;
  v_target_merchant_id uuid;
  v_target_location_id uuid;
  v_location_freshly_created boolean := false;
  v_merchant_freshly_created boolean := false;
  v_is_new_location_assignment boolean;
  v_is_new_merchant_assignment boolean;
begin
  -- Ownership check first, inside the same lock: never operate on a
  -- transaction the caller does not own, no matter what else is passed.
  select *
  into v_tx
  from public.transactions
  where id = p_transaction_id
    and user_id = auth.uid()
  for update;

  if not found then
    raise exception
      'reconcile_merchant_resolution: transaction % not found for the current user',
      p_transaction_id;
  end if;

  -- Validate everything the caller can control.
  if p_action is null or p_action not in ('attach_existing', 'create_new') then
    raise exception
      'reconcile_merchant_resolution: invalid action %', p_action;
  end if;

  if p_resolution_method is null or p_resolution_method not in (
    'exact_alias', 'fuzzy_brand', 'place_id_reconciled', 'places_search', 'user_locked'
  ) then
    raise exception
      'reconcile_merchant_resolution: invalid merchant_resolution_method %',
      p_resolution_method;
  end if;

  if p_resolution_confidence is null
    or p_resolution_confidence < 0 or p_resolution_confidence > 1 then
    raise exception
      'reconcile_merchant_resolution: resolution confidence % out of range',
      p_resolution_confidence;
  end if;

  if p_location_confidence is null
    or p_location_confidence < 0 or p_location_confidence > 1 then
    raise exception
      'reconcile_merchant_resolution: location confidence % out of range',
      p_location_confidence;
  end if;

  if p_google_place_id is null or btrim(p_google_place_id) = '' then
    raise exception 'reconcile_merchant_resolution: google_place_id is required';
  end if;

  if p_place_name is null or btrim(p_place_name) = '' then
    raise exception 'reconcile_merchant_resolution: place_name is required';
  end if;

  if p_geohash is null or btrim(p_geohash) = '' then
    raise exception 'reconcile_merchant_resolution: geohash is required';
  end if;

  if p_lat is null or p_lat < -90 or p_lat > 90 then
    raise exception 'reconcile_merchant_resolution: lat % out of range', p_lat;
  end if;

  if p_lng is null or p_lng < -180 or p_lng > 180 then
    raise exception 'reconcile_merchant_resolution: lng % out of range', p_lng;
  end if;

  if p_action = 'attach_existing' then
    if p_merchant_id is null then
      raise exception
        'reconcile_merchant_resolution: attach_existing requires p_merchant_id';
    end if;

    -- Reject clearly-invalid ids up front; also locks the row so this
    -- merchant cannot be concurrently deleted out from under this call.
    perform 1 from public.merchants where id = p_merchant_id for update;
    if not found then
      raise exception
        'reconcile_merchant_resolution: merchant % does not exist', p_merchant_id;
    end if;
  else
    if p_canonical_name_for_new is null or btrim(p_canonical_name_for_new) = '' then
      raise exception
        'reconcile_merchant_resolution: create_new requires a non-blank canonical_name_for_new';
    end if;

    -- `merchants.normalized_name_key` must be pre-normalized by the caller
    -- (same convention as normalizeForCompare() elsewhere in this repo) so
    -- it stays in the same normalization space as the text
    -- `lookup_merchant_candidates` is later queried with.
    if p_normalized_name_key_for_new is null or btrim(p_normalized_name_key_for_new) = '' then
      raise exception
        'reconcile_merchant_resolution: create_new requires a non-blank normalized_name_key_for_new';
    end if;

    if p_typical_place_types is not null and (
      cardinality(p_typical_place_types) > 32
      or octet_length(array_to_string(p_typical_place_types, ',')) > 2048
    ) then
      raise exception
        'reconcile_merchant_resolution: typical_place_types exceeds the bounded size';
    end if;
  end if;

  -- Place-ID-first, race-safe reconciliation. The advisory lock is scoped
  -- to this transaction (released automatically at commit/rollback) and
  -- keyed on the place id, so two concurrent reconciliations for the same
  -- brand-new place are fully serialized rather than racing each other into
  -- creating two merchants/locations for it.
  perform pg_advisory_xact_lock(hashtextextended('merchant_location:' || p_google_place_id, 0));

  select *
  into v_existing_location
  from public.merchant_locations
  where google_place_id = p_google_place_id
  for update;

  if found then
    -- Authoritative: never move an already-resolved place to a different
    -- merchant here. Evidence fields (not the hit_count counter) are always
    -- refreshed; hit_count is only bumped below once idempotency is checked.
    v_target_merchant_id := v_existing_location.merchant_id;
    v_target_location_id := v_existing_location.id;

    update public.merchant_locations
    set
      place_name = p_place_name,
      confidence = greatest(confidence, p_location_confidence),
      last_matched_at = now()
    where id = v_target_location_id;
  else
    if p_action = 'attach_existing' then
      v_target_merchant_id := p_merchant_id;
    else
      insert into public.merchants (
        canonical_name, normalized_name_key, vendor_category, typical_place_types
      )
      values (
        p_canonical_name_for_new, p_normalized_name_key_for_new, p_vendor_category,
        p_typical_place_types
      )
      returning id into v_target_merchant_id;
      v_merchant_freshly_created := true;
    end if;

    -- `on conflict ... do update` is a defense-in-depth collapse in case the
    -- advisory lock above were ever bypassed; it deliberately never writes
    -- merchant_id on conflict, so an authoritative existing row still wins.
    insert into public.merchant_locations (
      merchant_id, google_place_id, geohash_bucket, lat, lng, place_name, confidence
    )
    values (
      v_target_merchant_id, p_google_place_id, p_geohash, p_lat, p_lng, p_place_name,
      p_location_confidence
    )
    on conflict (google_place_id) do update
    set
      place_name = excluded.place_name,
      confidence = greatest(public.merchant_locations.confidence, excluded.confidence),
      last_matched_at = now()
    returning
      merchant_locations.id, merchant_locations.merchant_id, (xmax = 0)
    into v_target_location_id, v_target_merchant_id, v_location_freshly_created;
  end if;

  -- Idempotent counters: only a genuinely new assignment *for this
  -- transaction* (compared against what was already persisted before this
  -- call) increments a counter, and never when the row was just created by
  -- this same call (its default already counts as the first observation).
  v_is_new_location_assignment :=
    v_tx.merchant_location_id is distinct from v_target_location_id;
  v_is_new_merchant_assignment :=
    v_tx.merchant_id is distinct from v_target_merchant_id;

  if v_is_new_location_assignment and not v_location_freshly_created then
    update public.merchant_locations
    set hit_count = hit_count + 1
    where id = v_target_location_id;
  end if;

  if v_is_new_merchant_assignment and not v_merchant_freshly_created then
    update public.merchants
    set observation_count = observation_count + 1, last_observed_at = now()
    where id = v_target_merchant_id;
  end if;

  update public.transactions
  set
    merchant_id = v_target_merchant_id,
    merchant_location_id = v_target_location_id,
    merchant_resolution_method = p_resolution_method,
    merchant_resolution_confidence = p_resolution_confidence
  where id = p_transaction_id;

  return query select v_target_merchant_id, v_target_location_id;
end;
$$;

revoke execute on function public.reconcile_merchant_resolution(
  uuid, text, text, text, double precision, double precision, text, text,
  double precision, uuid, text, text, text, text[], double precision
) from public;
grant execute on function public.reconcile_merchant_resolution(
  uuid, text, text, text, double precision, double precision, text, text,
  double precision, uuid, text, text, text, text[], double precision
) to authenticated;
