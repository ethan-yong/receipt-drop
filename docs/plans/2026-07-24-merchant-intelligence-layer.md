# Feature: Merchant Intelligence & Canonicalization Layer

## Overview

A merchant identity model that separates a **merchant** (the brand — "Starbucks") from a **merchant location** (a specific branch — "Starbucks KLCC"), inserted into `enrich-transaction`'s existing resolution flow between the current alias fast-path and the Google Places call. It extends, rather than replaces, the global `merchant_aliases` cache introduced in `20260708000000_merchant_aliases.sql` and hardened for correction write-back in `20260723040000`/`20260724010000`. The goal is that a correction or a confident resolution at one branch of a chain measurably improves recognition of *other* branches of the same chain, and that OCR/LLM string noise ("STARBUCKS KLCC" / "STARBUKS" / "SBX KLCC") collapses onto one entity instead of independently rebuilding trust per geohash bucket.

## Problem Statement

`merchant_aliases` today keys directly on `(alias_text_normalized, geohash_bucket)` → a single resolved Google Place (`canonical_place_id`/`name`/`lat`/`lng`). This is fast and correct for the common "same OCR text, same location, seen before" case, but it has no representation of a brand that spans multiple locations: two branches of the same chain in two different geohash buckets are two entirely unrelated rows with no shared identity, so a correction made at one branch does nothing for recognition at another. There is also no place to attach brand-level signals (typical `vendor_category`, common Places types) independent of a single resolved location — every `enrich-transaction` call rebuilds that context from scratch via `resolveIncludedTypes()`/`buildLlmTextQueries()` on the LLM's per-receipt output alone. The result, cited directly in this feature's motivating examples: "STARBUCKS KLCC", "STARBUCKS COFFEE", "STARBUKS", "SBX KLCC" have no structural reason to ever be recognized as related, short of each individually clearing the existing Dice-coefficient + distance scoring bar against Google Places on every single enrichment.

## Goals

- Introduce persisted `merchants` (brand) and `merchant_locations` (branch) entities, distinct from the Google Place binding a location carries.
- Resolve an OCR/LLM merchant candidate to a canonical `merchant_id` (and, where determinable, a `merchant_location_id`) via a multi-signal confidence-scored pipeline layered onto `enrich-transaction`'s existing flow.
- Let a correction or high-confidence resolution at one location raise recognition confidence for *other* locations of the same brand.
- Reduce duplicate merchant identities caused by OCR/LLM text variance (abbreviation, misspelling, missing prefix/suffix, language) — automatically, without a new user-facing review step.
- Preserve every existing feedback-learning surface (`user_field_corrections`, `upsert_merchant_alias_from_correction`, `user_category_preferences`) as-is — this is an evolution of the merchant-alias layer, not a parallel system living beside it.

## Non-Goals

- **No new user-facing merge-review or admin UI.** Confirmed scope: all merge/dedup logic runs automatically, backend-only, using the same corroboration-gate pattern `merchant_aliases` already uses for disagreeing free-text corrections. There is no "is this the same merchant?" prompt anywhere in this spec.
- **No pre-seeded/curated merchant catalog.** Confirmed scope: every merchant entity is still created the first time it's observed, exactly like today — no hand-curated bootstrap list of known Malaysian chains ships with this feature.
- Not a rewrite of the Google Places integration. Places stays the source of truth for a specific branch's `lat`/`lng`/`place_id`; this layer sits above it, not in place of it.
- Not a change to OCR/LLM merchant extraction (`lib/domain/logic/merchant_extractor.dart`, `supabase/functions/_shared/receipt_understanding.ts`). This spec covers what happens *after* a merchant candidate string already exists.
- Not a redesign of category-preference (`user_category_preferences`) or misread-pattern (`ocr_misread_patterns`) learning — those stay exactly as documented in `docs/database/schema.md`, referenced here only where they interact.
- No cross-user "merchant profile" product surface (e.g. a browsable merchant directory). This is enrichment-accuracy infrastructure, not a new feature users see.
- No un-merge/split tooling for a bad automatic merge — see Edge Cases and Tradeoffs for why this is an accepted residual risk of the no-UI constraint, not an oversight.

## Proposed Solution

Extend `merchant_aliases` with `merchant_id`/`merchant_location_id` foreign keys (additive, nullable) rather than replacing its existing `canonical_*` columns, so the hot-path lookup (`lookup_merchant_alias`, hit on nearly every enrichment) keeps its current shape and cost. Add two new globally-scoped, locked-down tables — `merchants` and `merchant_locations` — following the exact `merchant_aliases` access pattern (RLS enabled, zero policies, access only through `security definer` RPCs with `EXECUTE` revoked from `PUBLIC`).

Insert one new resolution step into `enrich-transaction/index.ts`, between the existing alias fast-path (`lookup_merchant_alias`) and the existing Google Places search block: on an alias **miss**, before calling Places, check whether the LLM/OCR merchant text fuzzy-matches an already-known `merchants.normalized_name_key` closely enough to trust the *brand* even though this exact `(text, geohash)` pair hasn't been seen. If so, either attach to an existing nearby `merchant_location` or create a new one under the already-known merchant — skipping or narrowing the Places text-search uncertainty for a brand that's already been established elsewhere. If no fuzzy match clears the threshold, fall through to today's unmodified Places search + scoring, then reconcile the winning result against `merchant_locations` by `google_place_id` (a second, independent dedup path — see Decision Logic).

Every write path that currently touches `merchant_aliases` (`upsert_merchant_alias`, `upsert_merchant_alias_from_correction`) is extended to also create-or-update the corresponding `merchants`/`merchant_locations` rows, so corrections continue to flow through the single existing capture point (`ReceiptConfirmSheet` → `user_field_corrections`) with no new client-side work.

## User Experience

This is a backend-only enrichment-quality change — there is no new screen, state, or interruption. Concretely:

- **User flow**: unchanged. A receipt is captured, OCR/LLM-parsed, confirmed, and synced exactly as today; `enrich-transaction` runs its (now extended) resolution logic asynchronously in the background, same as the existing Places-matching step.
- **Important states**: none added. `pipeline_status` keeps its existing four values (`provisional`/`enriched`/`failed_enrichment`/`needs_review`); this feature never introduces a fifth.
- **Error handling**: a failure anywhere in the new resolution step (fuzzy-match query error, RPC failure) must degrade to exactly today's behavior — fall through to the unmodified Places search — never to `failed_enrichment` on its own. This mirrors the existing "alias lookup is a fast-path optimization, not required for correctness" comment already in `enrich-transaction/index.ts`.
- **Feedback mechanisms**: none new. The existing correction path (rename via `ReceiptConfirmSheet`, place override via `PlacePickerScreen` → `place_status='user_locked'`) remains the only way a user influences this system, unchanged in shape or timing.
- **Where a wrong merge would surface**: indirectly, as a wrong `merchant_normalized` or `place_*` value on an affected transaction — the same failure mode a bad Places match already produces today, correctable the same way (rename, or the place picker), with no new user-facing concept to explain.

## System Impact

- **Backend services**: `supabase/functions/enrich-transaction` is the primary integration point — new resolution logic inserted between the existing alias fast-path and the Places search block. `supabase/functions/_shared/place_matching.ts` gains new pure scoring helpers (fuzzy brand-match scoring), reused the same way `scoreCandidate`/`diceCoefficient` are today.
- **Database/storage**: two new tables (`merchants`, `merchant_locations`); additive columns on `merchant_aliases`; several new `security definer` RPCs; likely a new Postgres extension (`pg_trgm`, for indexed fuzzy name lookup) — same class of one-time extension enablement as `postgis` was for the map feature (`20260713000000_map_viewport_transactions.sql`).
- **AI/ML pipeline**: not modified. OCR (`services/ocr-api`) and the LLM receipt-understanding step are unchanged — this layer only consumes `understanding.merchant_name`/`vendor_category`/`google_place_types`, the same fields `enrich-transaction` already reads.
- **Client application**: no changes. `transactions.merchant_normalized` and `place_*` columns keep their current shape and meaning; the Flutter app never queries `merchants`/`merchant_locations` directly.
- **Infrastructure**: possible new Postgres extension enablement (`pg_trgm`); no new service, no new deploy target.
- **External integrations**: Google Places call *pattern* shifts (fewer blind text searches once a brand is already known — see LLM/Places Integration Points below), but no new external dependency.

## Technical Design

### Merchant Identity Model

Two entities, deliberately separated:

- **Merchant** (brand): "Starbucks", "McDonald's", "Tesco" — the thing a user thinks of as *who* they bought from. Carries brand-level aggregate signals (dominant vendor category, typical Places types, overall observation count/confidence) that no single location's data alone represents.
- **Merchant location** (branch): "Starbucks KLCC", "Starbucks Mid Valley" — a specific physical place, bound 1:1 to at most one Google `place_id` once resolved (nullable before first Places resolution, to allow a GPS-cluster-only location record). Carries the same kind of location-scoped data `merchant_aliases.canonical_*` carries today.

Separating them is what allows a correction/observation at one branch to raise confidence for *the brand* without falsely implying every branch shares the exact same GPS coordinates — and lets brand-level signals (e.g. "this chain is always `Food & Drink`") bias Places search for a *new, never-seen* branch of a known chain, which a purely per-location cache structurally cannot do.

### Data Model

**`merchants`** (new, global, no `user_id`):
- `id` — identity
- `canonical_name` — best-known display name (preferring a Places `displayName` over raw OCR when both exist, since Places names are cleaner — see Decision Logic)
- `normalized_name_key` — `normalizeForCompare()`'d canonical name, the fuzzy-match lookup key
- `vendor_category` (nullable) — dominant category observed across this merchant's locations/corrections, same vocabulary as the LLM's `vendor_category`
- `typical_place_types` (nullable array) — union/most-common Google Place types across this merchant's locations
- `observation_count` — rolled-up count across all locations/aliases under this merchant
- `confidence` — brand-identity confidence, decayed on read with the same 90-day half-life pattern `lookup_merchant_alias`/`lookup_category_preference` already apply
- `created_at`, `last_observed_at`

**`merchant_locations`** (new, global, FK to `merchants`, cascade delete):
- `id`, `merchant_id`
- `google_place_id` (nullable — null until a Places resolution succeeds for this specific branch)
- `geohash_bucket` (same precision-7 convention as `merchant_aliases`)
- `lat`/`lng` (nullable)
- `place_name` (nullable — Places' own `displayName` for *this* branch, distinct from `merchants.canonical_name`)
- `confidence`, `hit_count`
- `created_at`, `last_matched_at`
- Uniqueness on `(merchant_id, geohash_bucket, google_place_id)`, mirroring `merchant_aliases`' existing unique-constraint shape

**`merchant_aliases`** (existing table, extended additively): gains nullable `merchant_id`/`merchant_location_id` FKs alongside its current `canonical_place_id`/`canonical_name`/`canonical_lat`/`canonical_lng` columns. The existing `(alias_text_normalized, geohash_bucket)` lookup key and unique constraint are untouched — this keeps `lookup_merchant_alias`'s hot-path query cost identical (still one indexed lookup) while giving each alias row a place to point at a durable entity. New alias rows populate both the legacy `canonical_*` columns and the new FKs from day one; existing rows are resolved by a one-time backfill (see Rollout Plan), not required before ship.

**Correction history**: no schema change to `user_field_corrections` — it remains the single capture point (`ReceiptConfirmSheet._buildFieldCorrections()`), unchanged in shape. Merchant/location resolution happens downstream, inside `upsert_merchant_alias_from_correction`, which is extended to also resolve/attach `merchant_id`/`merchant_location_id` at write-back time.

**Confidence scores**: stored per-row on `merchants.confidence` and `merchant_locations.confidence` (raw, as-written), decayed only on read — same "decay belongs on the read path, not the write path" principle already established for `merchant_aliases`/`user_category_preferences` in the 2026-07-24 hardening pass, applied consistently here rather than inventing a different convention for the new tables.

### Resolution Pipeline Overview

Sits inside `enrich-transaction/index.ts`, after the existing precomputed-understanding/payment-receipt handling, replacing the single alias-lookup-then-Places flow with three ordered stages (full rules in Decision Logic):

1. **Exact alias hit** (unchanged from today) — `(alias_text_normalized, geohash_bucket)` lookup; if hit, resolve directly from the alias row's (now-populated) `merchant_id`/`merchant_location_id`, no Places call.
2. **Fuzzy brand match** (new) — on an alias miss, check the normalized merchant text against known `merchants.normalized_name_key` values via an indexed trigram/Dice similarity query. A strong match lets the brand be trusted even for a location never seen before, narrowing (or skipping) the Places identity search.
3. **Places search + place-id reconciliation** (existing Places call, extended) — unchanged scoring (`scoreCandidate`, `adjustScoreForTypeMatch`), but the winning candidate's `place_id` is additionally checked against `merchant_locations` — if that exact place is already known under some merchant (reached previously via different OCR text), attach to the existing merchant instead of creating a new one.

### Confidence Model

No single signal is authoritative (per requirement). A weighted blend, kept as a hand-inspectable formula rather than a learned model — consistent with this codebase's explicit heuristic-over-ML precedent (`docs/system/decisions.md`, adaptive-OCR and feedback-hardening entries):

- **Text similarity** (0.45 weight) — Dice coefficient between the OCR/LLM merchant text and the candidate merchant's `canonical_name`, reusing the existing `diceCoefficient()`.
- **Location proximity** (0.20 weight) — 1.0 on an exact alias/location hit, `distanceScore()` (existing haversine-based exponential decay) when resolved via a nearby-but-not-exact `merchant_location`, 0 when the match is brand-only with no nearby location at all.
- **Places type match** (0.15 weight) — existing `adjustScoreForTypeMatch()` output, normalized to 0..1.
- **Corroboration** (0.10 weight) — the existing hit-count-based promotion formula from `upsert_merchant_alias_from_correction`, decayed.
- **Popularity** (0.10 weight) — log-scaled, capped `observation_count`, a tie-breaker only — deliberately low-weighted so a high-volume *wrong* merge candidate can't dominate a lower-volume but textually-closer correct one.

All resulting confidences clamp to `[0.05, 0.97]`, matching the existing clamp range from the 2026-07-24 hardening pass. An exact alias hit (stage 1) bypasses this formula entirely, exactly as it does today — it's already a verified resolution, not a fresh guess.

### Learning Integration

- Corrections continue to flow through the one existing capture point (`user_field_corrections` → `upsert_merchant_alias_from_correction`), which is extended to resolve `merchant_id` during write-back — so a correction at any one branch strengthens the shared `merchants` row, not just that branch's alias.
- Two independent conflict axes, resolved with the existing corroboration-gate shape (disagreement written as a low-confidence competing row, promoted only after repeated recurrence — unchanged threshold/mechanics, just applied at a second level):
  - **Location-level**: does this alias point to location A or B under the *same* merchant.
  - **Merchant-level**: is this actually a different brand entirely (e.g. a genuinely independent "Kopi Starbuck" copycat that must never merge into "Starbucks"). This is why the fuzzy-match gate (Decision Logic, stage 2) is deliberately conservative — a low-confidence fuzzy match must create a new, separate merchant rather than attempt a merge.
- Recency decay applies independently at all three levels (alias, location, merchant) using the existing 90-day half-life constant — a merchant not observed in months should decay for auto-merge purposes even if one of its locations is still fresh, since brand drift/rebrand risk grows with staleness.
- LLM prompts are **not** modified by this feature. Server-side prompt injection of "known merchant candidates near this GPS" would need `services/ocr-api` to query Postgres at prompt-build time, which it cannot do today (the same documented gap already blocking `ocr_misread_patterns` consumption, per `docs/system/decisions.md`'s 2026-07-24 entry). See LLM Integration Points below for the approach given this constraint.

### Duplicate Prevention

Two independent, fully automatic dedup paths — no manual confirmation step, per confirmed scope:

1. **Text-fuzzy match**: a new merchant candidate's normalized text is checked against existing `merchants.normalized_name_key` values; a match clearing the merge threshold (proposed 0.82 Dice — a first-cut constant pending batch tuning, same "provisional pending measurement" caveat as this codebase's other heuristic thresholds) attaches to the existing merchant instead of creating a new one, gated additionally by geohash proximity (never merge on name similarity alone — see Edge Cases).
2. **Place-id match**: once Places independently resolves two differently-worded receipts to the same `place_id`, that's treated as ground truth for identity — the second `merchant_location` created for that place attaches to whatever merchant the *first* one already belongs to, overriding a low-confidence text mismatch (with a corroboration gate for the rebrand edge case — see Edge Cases).

The 0.82 threshold is intentionally conservative: this design has no human review step to catch an incorrect merge, so it must strongly prefer creating a duplicate merchant (a data-quality nuisance, self-correcting over time via low observation counts) over incorrectly merging two distinct businesses (a data-quality error that actively degrades enrichment for both). No automatic un-merge/split capability exists in this spec's scope — see Edge Cases and Tradeoffs.

### LLM Integration Points

- **Before LLM** — not recommended for v1. Would require a location-aware Postgres query at prompt-build time inside `services/ocr-api`'s Python request handler, which has no Postgres connectivity today. Out of scope until that infrastructure exists (tracked as the same class of gap already noted for `ocr_misread_patterns`).
- **After LLM (recommended, primary integration point)** — the resolution pipeline above already runs immediately after `understanding.merchant_name` is available, inside `enrich-transaction`. This *is* the "validate extracted merchant" step; no new LLM call is introduced, it's a new step in already-existing post-LLM code.
- **During enrichment (recommended, secondary use)** — once stage 2 (fuzzy brand match) identifies a probable existing merchant *before* Places is called, its `typical_place_types` can pre-seed/override `resolveIncludedTypes()`'s output for the Nearby Search call, and a known `merchant_location.google_place_id` for that brand near this geohash can be tried via a direct Places Details lookup before falling back to blind text/nearby search — cheaper and more precise once a brand is established.

## Decision Logic

Ordered resolution rules, replacing the single alias-lookup-then-Places block in `enrich-transaction/index.ts`:

- **When** the LLM/OCR merchant text + geohash bucket exactly matches an existing `merchant_aliases` row (today's existing fast path) — **then** resolve `merchant_id`/`merchant_location_id` directly from that row, skip everything below, no Places call. Unchanged from today.
- **When** no exact alias exists, **then** normalize the candidate text and query `merchants.normalized_name_key` for the best fuzzy match (indexed trigram/Dice similarity, top-N candidates only).
  - **If** the best match's similarity ≥ 0.82 **and** that merchant has an existing `merchant_location` within the same or an adjacent geohash bucket (adjacent tolerated for GPS-drift, same reasoning as `merchant_aliases`' precision-7 bucket choice) — **then** treat as a known branch: attach to that `merchant_location` (optionally still issuing a lightweight Places Details call only if `google_place_id` is still null on that row), skip the full Places text/nearby search.
  - **If** the best match's similarity ≥ 0.82 **but** that merchant has no location near this geohash — **then** treat as a known brand, new branch: skip the *identity* uncertainty (brand is already trusted) but still call Places, scoped to "find this brand's location near here" rather than "identify who this receipt is from," and create a new `merchant_location` under the existing `merchant_id`.
  - **If** the best match's similarity < 0.82 (or no candidates exist) — **then** fall through to the existing, unmodified Places text+nearby search and `scoreCandidate`/`adjustScoreForTypeMatch` scoring.
- **When** a Places winner is chosen (whether via the fallback above or the brand-known/new-branch path), **then** check `merchant_locations` for an existing row with that exact `google_place_id`.
  - **If** found **and** the winning candidate's name similarity to that location's existing merchant's `canonical_name` is reasonably high (not a rebrand signal) — **then** attach to the existing `merchant_id`/`merchant_location_id`, regardless of how the text-fuzzy stage scored — place-id equality is stronger ground truth than text similarity.
  - **If** found **but** name similarity to the existing merchant is very low (a possible rebrand) — **then** do **not** silently reattach; write this as a competing, low-confidence observation on the *existing* `merchant_location` (mirroring the disagreeing-free-text-correction pattern) rather than either merging outright or blindly creating a duplicate location at the same coordinates — require repeated recurrence before the new name displaces the old one, exactly as `upsert_merchant_alias_from_correction`'s existing 3-recurrence promotion already works for text corrections.
  - **If** not found — **then** this is a genuinely new merchant: create a new `merchants` row (`canonical_name` = the Places `displayName`, preferred over raw OCR text since Places' name is more reliable) and a new `merchant_location` row under it.
- **On write-back** (both the algorithmic `upsert_merchant_alias` ≥0.85-confidence path and the correction-triggered `upsert_merchant_alias_from_correction` path) — **then** in addition to today's existing writes, bump `merchants.observation_count`/`last_observed_at` and `merchant_locations.hit_count`/`last_matched_at` for whichever entity the resolution above attached to.
- **On any failure** in the new stages (fuzzy-match query error, RPC failure, timeout) — **then** fall through to the pre-existing Places search unmodified, exactly as today's alias-lookup try/catch already falls through on failure. This step must never be able to fail the overall enrichment on its own.

## Edge Cases

- **Independent stores with similar names** (two unrelated "Kopitiam" shops) — text similarity alone would false-merge; mitigated by requiring geohash proximity or place-id equality alongside name similarity, never merging on name similarity in isolation (Decision Logic, stage 2's location-proximity requirement).
- **Franchise locations under different legal names, same brand signage** — if Places' own `displayName` already normalizes this, no special handling needed; if it doesn't, this is a known false-merge risk under the automatic-only design (e.g. two independently-run "Family Mart" franchises), accepted as the same class of risk `merchant_aliases` already carries today as a global, cross-user cache.
- **Rebranded businesses** (a location's OCR/LLM text abruptly changes at the same `google_place_id`) — handled by the "low name-similarity at existing place-id" branch of Decision Logic: never silently reattach; require repeated recurrence of the new name before it displaces the old merchant's claim on that location, using the same corroboration-gate mechanics already proven for free-text alias corrections.
- **Multiple branches, same brand, inconsistent vendor_category reads** (e.g. a "Starbucks" inside a "7-Eleven" combo store) — `merchants.vendor_category` is stored as a *dominant aggregate*, never authoritative; `enrich-transaction` continues to prefer the per-transaction LLM `vendor_category` for category-guessing, using the merchant aggregate only as a Places-type search hint — consistent with `user_category_preferences`' existing "only override when the request's own signal is already low-confidence" pattern.
- **Temporary pop-up stores** — no special handling required; a pop-up naturally accrues a low `observation_count` that never grows further once it closes, and the existing 90-day decay handles staleness without needing explicit "temporary" detection.
- **User-created nicknames** (e.g. renaming "SF CAFE SDN BHD" to "Selera Food Court") — unchanged from today's existing free-text correction path; this spec only ensures the resulting write-back resolves through the same `merchant_id` logic as any other correction. Note this spec does not revisit the existing design choice that a private nickname correction still becomes a *global* alias (see Security Considerations).
- **OCR mistakes creating fake merchants** — `isUsableMerchantText()`'s existing length/garble gate remains the first filter; a merchant created from one low-confidence observation naturally carries low `observation_count`/`confidence`, so it can never win a fuzzy-merge decision against an established brand (weighted, not binary, per the Confidence Model) and simply never accumulates further hits — no explicit cleanup job proposed for v1 (see Performance Considerations, storage growth).
- **Concurrent enrichment race** — two simultaneous `enrich-transaction` invocations could both attempt to create the same brand-new merchant at once. Mitigated the same way `upsert_merchant_alias_from_correction` already handles concurrent write-back: a unique constraint (on `merchants.normalized_name_key` + a coarse identity key, and on `merchant_locations`' `(merchant_id, geohash_bucket, google_place_id)`) with upsert-on-conflict, never check-then-insert.
- **No un-merge/split path** — a bad automatic merge (once made) has no detection or reversal mechanism in this spec's scope. Given the confirmed no-UI constraint, this is an accepted residual risk, mitigated only by the conservative 0.82 merge threshold — see Tradeoffs.

## Performance Considerations

- **Hot path unchanged**: an exact alias hit (Decision Logic stage 1) costs exactly what it costs today — one indexed lookup, no new joins.
- **Fuzzy-match query cost**: only runs on an alias miss — already the "slow path" that calls Google Places today. Bounded via an indexed trigram/Dice similarity query (Postgres `pg_trgm` extension, top-N candidates capped, e.g. 20) run concurrently with the existing Places `Promise.all` block rather than serialized in front of it, so it adds parallel latency, not additive latency, in the common case where it doesn't short-circuit the Places call.
- **Storage growth**: `merchants`/`merchant_locations` grow with the same OCR-mistake/pop-up-store long-tail already true of `merchant_aliases` today — no pruning strategy proposed for v1, same "provisional, pending real usage data" caveat as other unbounded-growth tables in this schema.
- **Client caching**: not applicable — this is entirely server-side; the client never queries `merchants`/`merchant_locations` and continues to see only `merchant_normalized`/`place_*` on its own transactions, unchanged.
- **Cost implications**: the brand-known/new-branch path (Decision Logic) is expected to *reduce* average Google Places quota usage per enrichment over time (a known brand needs a narrower or Details-only lookup instead of a blind text+nearby search), though this isn't guaranteed pre-launch — recommend measuring via `scripts/process_receipts.ps1` batch runs before and after enabling the flag.

## Security Considerations

- **No new auth surface**: `merchants`/`merchant_locations` follow the exact `merchant_aliases` locked-down pattern — RLS enabled with zero policies, `EXECUTE` revoked from `PUBLIC` and granted only to `authenticated` on the RPCs that touch them.
- **Data privacy**: both new tables carry business identity/location data only (brand names, branch names, Places coordinates) — the same non-sensitive-per-user data class `merchant_aliases` already shares globally today. Neither table has a `user_id` column. A user's free-text nickname correction still becomes a *global* alias exactly as it does today — this spec does not add a private, per-user merchant-identity tier (see Tradeoffs for why that's deferred, not solved).
- **Abuse case**: a malicious or compromised client repeatedly feeding `enrich-transaction` fabricated merchant text could pollute the shared merchant catalog — this risk already exists in today's `merchant_aliases` design and isn't newly introduced here. The corroboration/conservative-merge thresholds incidentally rate-limit the damage a single bad actor's receipts can do, since any one write only nudges confidence rather than overwriting an established row outright — the same protection today's `≥0.85`-confidence alias-save threshold already relies on.

## Tradeoffs

- **Additive `merchant_id` columns on `merchant_aliases` vs. replacing its `canonical_*` columns outright**: chosen to keep the hot-path table's existing shape and cost untouched, and to let new alias rows populate the new FKs immediately while a backfill (not blocking ship) resolves historical rows. Rejected the full-replacement alternative — it would touch every existing alias row and every `enrich-transaction` code path that reads `canonical_place_id` directly in one migration, a materially bigger, riskier single change for no functional benefit over the additive approach.
- **Dice-coefficient/trigram fuzzy matching vs. an ML/embedding-based similarity model**: chosen to stay consistent with this codebase's explicit, repeatedly-stated heuristic-over-ML precedent (`docs/system/decisions.md`'s adaptive-OCR and feedback-hardening entries both name this directly). An embedding model would also require new infrastructure (a vector store, an embedding call) neither the OCR nor enrichment stack has today.
- **Fully automatic merge/dedup vs. a human-in-the-loop review UI**: rejected the review-UI alternative per this spec's confirmed scope, though it is the standard real-world mitigation for the "no un-merge" residual risk this design accepts. Worth revisiting if false-merges prove materially damaging post-launch — flagged explicitly rather than silently assumed away.
- **Global-only merchant identity vs. a per-user private tier** (mirroring `user_category_preferences`' separate personal scope): rejected as out of scope for this spec — it wasn't part of the requested design, and would be a real behavioral change to how nickname corrections are shared today, not a natural extension of the existing global-cache model.
- **No seed/curated chain catalog vs. bootstrapping known Malaysian chains**: rejected per confirmed scope. Fully emergent matches today's system exactly and avoids an ongoing curation-maintenance burden; deferred as a possible future enhancement once the entity model itself exists to import into, rather than attempted here.

## Implementation Guidance

Suggested order of work:

1. Migrations: `merchants` + `merchant_locations` tables, plus additive nullable `merchant_id`/`merchant_location_id` columns on `merchant_aliases`. No behavior change yet — new columns unpopulated, feature flag off.
2. Extend `lookup_merchant_alias`/`upsert_merchant_alias`/`upsert_merchant_alias_from_correction` to read/write the new FKs and bump `merchants`/`merchant_locations` counters, without changing their existing return shape (additive fields only, so `enrich-transaction`'s current call sites keep working unmodified until step 4).
3. Add the new fuzzy-brand-match RPC (a `security definer` function following the exact `merchant_aliases` access pattern) — this is the one genuinely new piece of resolution logic (Decision Logic's stage 2).
4. Wire `enrich-transaction/index.ts`: insert the new stage between the existing alias-lookup block and the existing Places-search block, behind a feature flag (e.g. `MERCHANT_INTELLIGENCE_ENABLED`, mirroring the `ADAPTIVE_OCR_ENABLED`/`LLM_CLEANUP_ENABLED` env-flag precedent).
5. Shadow-mode logging first (mirroring `ADAPTIVE_OCR_SHADOW`'s pattern: log what the new stage *would* have decided, without acting on it) to validate against real traffic before flipping the flag live.
6. One-time backfill script (not a migration — mirror `supabase/scripts/20260723_backfill_category_preferences.sql`'s manual-run precedent) to resolve historical `merchant_aliases` rows into `merchants`/`merchant_locations`, clustering by existing `canonical_place_id` first (ground truth), then fuzzy name grouping for rows sharing a place.
7. Flip the flag on; once validated, the flag and any dual-write scaffolding can be removed.

Files to inspect first: `supabase/functions/enrich-transaction/index.ts` (primary integration point — read the full alias-fast-path-through-Places-scoring block before touching anything), `supabase/functions/_shared/place_matching.ts` (scoring primitives to reuse/extend), `supabase/migrations/20260708000000_merchant_aliases.sql` and `20260723040000_merchant_alias_correction_writeback.sql` (current shape being extended), `docs/database/schema.md` and `docs/system/decisions.md` (update both post-implementation, per this repo's own documentation-maintenance instruction in `CLAUDE.md`).

Real risks to flag, not generic "test thoroughly" advice:
- The `pg_trgm`-based fuzzy query's performance at production scale is untested — same "provisional pending batch tuning" category as most other heuristic thresholds in this codebase; verify via `scripts/process_receipts.ps1` before trusting default-on.
- During the additive-columns transition window, `enrich-transaction` reads/writes both the legacy `canonical_*` columns and the new `merchant_id` columns on the same `merchant_aliases` rows — a real, if temporary, dual-write consistency risk worth an explicit code comment (this codebase's own convention, seen throughout `docs/system/decisions.md`, is to document exactly this kind of transitional dual-state explicitly rather than leave it implicit).
- The 0.82 merge threshold and the "adjacent geohash bucket" tolerance are both first-cut constants with no batch data behind them yet — do not treat them as final without a tuning pass against real receipts, consistent with how every other threshold in this codebase (CLAHE contrast gate, illumination detector, OCR budget) was explicitly staged behind a flag before being trusted default-on.

## Testing Strategy

- **Merchant recognition accuracy**: extend `place_matching.test.ts` with fixture pairs of OCR-variant merchant strings (the STARBUCKS example set from this feature's own motivating case) against expected `merchant_id`/`merchant_location_id` resolution outcomes, in the same style as the existing `scoreCandidate`/`diceCoefficient` unit tests.
- **Duplicate reduction — both directions**: a regression fixture set of legitimately-different-but-similar-looking merchant names (the "independent stores with similar names" edge case) asserting they do **not** merge, alongside the true-positive variant set that should merge. Testing only the true-positive direction would miss the failure mode this design is most exposed to (an unreversible false merge).
- **Concurrency**: a dedicated test for the concurrent-new-merchant race (two simultaneous inserts racing the same `normalized_name_key` + geohash), asserting the unique-constraint-plus-upsert path collapses to exactly one `merchants` row.
- **Enrichment success rate**: before/after batch comparison using the existing `scripts/process_receipts.ps1` tooling against a real receipt-image folder — this repo's standard mechanism for validating heuristic-threshold changes without needing live production traffic.
- **User correction reduction**: not meaningfully testable pre-launch (no usage data exists yet) — recommend tracking correction rate per merchant as a post-launch rollout-validation metric rather than a pre-ship CI gate.

## Rollout Plan

- Ship behind an env-gated flag (`MERCHANT_INTELLIGENCE_ENABLED` on `enrich-transaction`, default off), mirroring the existing `ADAPTIVE_OCR_ENABLED`/`LLM_CLEANUP_ENABLED`/`PREPROCESS_ILLUMINATION` precedent in this codebase.
- Migration and code land fully additive with the flag off first (steps 1-4 in Implementation Guidance) — no behavior change, safe to merge and deploy ahead of activation.
- Shadow-mode logging (step 5) validates the new resolution stage's decisions against real traffic before it's allowed to affect any transaction.
- Backfill (step 6) runs once, manually, before flipping the flag on for real — new rows work correctly with the flag off regardless, so this isn't a hard blocker, only a completeness step for historical data.
- No client version dependency and no staged client rollout needed — this is entirely server-side; the flag can go straight from off to fully-on once shadow-mode validation looks correct, unlike a client-visible feature that would need a phased release-train rollout.
- **Rollback**: flag off reverts to exactly today's `merchant_aliases`-only flow. Since phases 1-6 are additive (nothing existing is dropped, renamed, or overwritten), rollback carries no data-loss risk at any point before the flag is flipped, and even after, since the legacy `canonical_*` columns keep being populated throughout.
- **Backward compatibility**: `transactions.merchant_normalized`/`place_*` stay unchanged in shape and meaning throughout every phase — this is purely an internal enrichment-quality upgrade, invisible to the client app and to any existing consumer of those columns.
