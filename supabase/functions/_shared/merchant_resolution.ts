// Pure brand-candidate derivation and merchant decision scoring for the
// merchant-intelligence layer (see docs/plans/2026-07-24-merchant-intelligence
// -layer.md and the accompanying architecture review). No network or DB
// access — retrieval of the bounded merchant-candidate list (pg_trgm) and
// persistence of the resulting decision (the reconciliation RPC) are owned
// by later rollout tasks. This module only reasons over data already handed
// to it, so it can be unit-tested in complete isolation and safely run in
// "shadow" mode (score/log only, no writes) before it is ever trusted to
// mutate anything.
//
// Deliberately does not receive or reason about GPS/proximity: the only
// signals it uses are (a) the receipt-side brand-candidate text derived from
// the LLM's understanding of the receipt, and (b) the Google Places winner's
// display name/types already chosen for this transaction by the existing
// Places flow. See "Recommended Architecture Approach" in the plan for why
// GPS-only/text-only agreement is rejected as an attach signal.

import {
  diceCoefficient,
  isUsableMerchantText,
  normalizeForCompare,
} from "./place_matching.ts";

// ---------------------------------------------------------------------------
// A. Brand-candidate derivation
// ---------------------------------------------------------------------------

/** The subset of `ReceiptUnderstanding` this module actually needs, kept
 * narrow/duck-typed rather than importing the full interface so this file
 * has zero dependency surface on the OCR/LLM schema beyond these fields. */
export interface UnderstandingForBrandDerivation {
  merchant_name: string | null | undefined;
  merchant_search_queries: string[] | null | undefined;
  location_clues: string[] | null | undefined;
}

/**
 * Malaysian legal-entity / generic-suffix tokens stripped only from the very
 * end of a candidate string, so a legally-suffixed and unsuffixed variant of
 * the same business ("Restoran Anwar Maju Sdn Bhd" vs "Restoran Anwar
 * Maju") don't score as a false brand mismatch. Deliberately narrow: this is
 * not a general company-suffix remover (no "Ltd", "LLC", "Inc", ...) — just
 * the handful of forms that actually show up on Malaysian receipts and in
 * this repo's own fixtures. Extend only with evidence, not speculatively.
 */
const LEGAL_SUFFIX_PATTERN =
  /[\s,.]+\b(sdn\.?\s*bhd\.?|bhd\.?|enterprise)\.?\s*$/i;

/** Strips at most a couple of trailing legal/generic suffixes (handles the
 * rare "X Enterprise Sdn Bhd" double-suffix case) and falls back to the
 * original string if stripping would leave nothing. */
export function stripLegalSuffix(s: string): string {
  let out = s;
  for (let i = 0; i < 3; i++) {
    const next = out.replace(LEGAL_SUFFIX_PATTERN, "").trim();
    if (next === out || next.length === 0) break;
    out = next;
  }
  return out.length > 0 ? out : s;
}

/** Case-insensitively removes every occurrence of each `substrings` entry
 * from `text`, then collapses the resulting whitespace gaps. */
function stripSubstrings(text: string, substrings: string[]): string {
  let out = text;
  for (const raw of substrings) {
    const clue = raw?.trim();
    if (!clue) continue;
    const idx = out.toLowerCase().indexOf(clue.toLowerCase());
    if (idx === -1) continue;
    out = out.slice(0, idx) + out.slice(idx + clue.length);
  }
  return out.replace(/\s+/g, " ").trim();
}

/**
 * Derives an ordered list of brand-candidate strings from one receipt's LLM
 * understanding — most likely location/branch-stripped brand name first.
 * Never throws; returns `[]` for a null/blank `merchant_name` or entirely
 * empty input.
 *
 * Priority, matching the plan's specified fallback chain:
 * 1. A `merchant_search_queries` entry that, after stripping any
 *    `location_clues` substrings out of it, is non-empty and still differs
 *    from the raw `merchant_name` — i.e. a genuinely distinct, generic
 *    variant the LLM already produced (the "McDonald's Pavilion KL" /
 *    "McDonald's" pattern).
 * 2. `merchant_name` itself with `location_clues` substrings stripped out,
 *    only when that stripping actually removed something and the remainder
 *    is still long enough to trust as a brand name on its own.
 * 3. `merchant_name` unchanged.
 *
 * Every candidate additionally has trailing Malaysian legal-entity suffixes
 * normalized off (see `stripLegalSuffix`), and the final list is deduped by
 * `normalizeForCompare` key (same convention as `buildTextSearchQueries`).
 */
export function deriveBrandCandidates(
  input: UnderstandingForBrandDerivation,
): string[] {
  const merchantName = input?.merchant_name?.trim() || null;
  if (!merchantName) return [];

  const searchQueries = Array.isArray(input.merchant_search_queries)
    ? input.merchant_search_queries
    : [];
  const locationClues = (
    Array.isArray(input.location_clues) ? input.location_clues : []
  ).filter((c): c is string => typeof c === "string" && c.trim().length > 0);

  const raw: string[] = [];
  const merchantNameKey = normalizeForCompare(merchantName);

  // 1. A distinct, location-clue-stripped search-query variant.
  for (const q of searchQueries) {
    const trimmed = typeof q === "string" ? q.trim() : "";
    if (!trimmed) continue;
    const stripped = stripSubstrings(trimmed, locationClues);
    if (stripped.length === 0) continue;
    const strippedKey = normalizeForCompare(stripped);
    if (strippedKey.length === 0 || strippedKey === merchantNameKey) continue;
    raw.push(stripLegalSuffix(stripped));
  }

  // 2. merchant_name with location clues stripped out of it directly.
  const strippedMerchantName = stripSubstrings(merchantName, locationClues);
  if (
    strippedMerchantName.length > 0 &&
    strippedMerchantName.length < merchantName.length &&
    isUsableMerchantText(stripLegalSuffix(strippedMerchantName))
  ) {
    raw.push(stripLegalSuffix(strippedMerchantName));
  }

  // 3. merchant_name unchanged (suffix-normalized), as the last resort.
  raw.push(stripLegalSuffix(merchantName));

  const seen = new Set<string>();
  const result: string[] = [];
  for (const candidate of raw) {
    const key = normalizeForCompare(candidate);
    if (key.length === 0 || seen.has(key)) continue;
    seen.add(key);
    result.push(candidate);
  }
  return result;
}

// ---------------------------------------------------------------------------
// B. Pure merchant decision scoring
// ---------------------------------------------------------------------------

/** Below this Dice score against a candidate's `canonical_name`, the
 * receipt-side brand text is not considered to agree with that candidate.
 * Rollout configuration, not a durable schema constant — tune from shadow
 * fixtures, not in-place magic numbers. */
export const BRAND_AGREEMENT_THRESHOLD = 0.6;

/** Below this Dice score against a candidate's `canonical_name`, the Google
 * Places winner's display name is not considered to agree with that
 * candidate. Same rollout-configuration status as `BRAND_AGREEMENT_THRESHOLD`
 * — kept as a separate constant even though it currently has the same value,
 * since the two signals (OCR-derived text vs. a Places-returned name) have
 * different noise characteristics and may need to diverge once shadow data
 * exists. */
export const PLACES_AGREEMENT_THRESHOLD = 0.6;

/** Multiplier applied to a candidate's Places-side agreement score when the
 * candidate's `typical_place_types` and the Places winner's `types` are both
 * known but share nothing — the same "don't hard-filter, just sink the
 * score" stance as `receipt_understanding.ts`'s `TYPE_MISMATCH_PENALTY`, and
 * kept at the same value for consistency, but defined independently here
 * since this module must stay free of any dependency on the OCR/LLM schema
 * module. Neutral (no penalty) when either side has no type information. */
export const TYPE_AGREEMENT_MISMATCH_PENALTY = 0.6;

/** A merchant candidate as retrieved (by a future `pg_trgm` lookup, out of
 * scope for this module) and handed to the decision function. */
export interface MerchantCandidateForScoring {
  id: string;
  canonical_name: string;
  typical_place_types?: string[] | null;
}

/** The Google Places winner already chosen for this transaction by the
 * existing (unmodified) Places flow — display name and types only, no
 * coordinates, since this module must not need or use GPS. */
export interface PlacesWinnerForScoring {
  name: string | null | undefined;
  types?: string[] | null;
}

export type MerchantResolutionAction = "attach_existing" | "create_new";

/** Machine-readable outcome reasons, suitable for shadow-mode logging
 * (see the plan's "Shadow logs expose excessive receipt context" risk —
 * this module never receives raw receipt/OCR text, so there is nothing
 * sensitive to accidentally include here in the first place). */
export type MerchantResolutionReasonCode =
  | "no_brand_candidate"
  | "brand_candidate_low_signal"
  | "no_merchant_candidates"
  | "no_places_winner"
  | "brand_and_places_agree"
  | "no_candidate_agreement";

export interface MerchantResolutionDecision {
  action: MerchantResolutionAction;
  /** Populated only when `action === "attach_existing"`. */
  merchantId: string | null;
  /** Best brand-candidate text to use as a new merchant's `canonical_name`
   * when `action === "create_new"` (or, informationally, the brand text
   * that was actually scored either way); null only when no usable brand
   * candidate existed at all. */
  canonicalNameForNew: string | null;
  /** 0..1. The winning candidate's combined agreement score when attaching;
   * a fixed 0 for every "create_new" outcome — this module has no positive
   * evidence a *new* merchant record is correct, only that it couldn't
   * confirm an existing one, so it deliberately does not manufacture a
   * confidence number for that case. */
  confidence: number;
  reason: MerchantResolutionReasonCode;
  /** The top usable brand-candidate text that was actually scored, if any. */
  brandCandidate: string | null;
}

function typesAgree(
  a: string[] | null | undefined,
  b: string[] | null | undefined,
): boolean | null {
  if (!a || a.length === 0 || !b || b.length === 0) return null;
  const bSet = new Set(b);
  return a.some((t) => bSet.has(t));
}

interface CandidateAgreement {
  candidate: MerchantCandidateForScoring;
  brandScore: number;
  placesScore: number;
  qualifies: boolean;
  /** min(brandScore, placesScore) — a candidate is only as strong as its
   * weakest independently-required signal, consistent with never attaching
   * on either signal alone. Used to rank multiple qualifying candidates. */
  combinedScore: number;
}

function scoreCandidateAgreement(
  usableBrandCandidates: string[],
  placesWinner: PlacesWinnerForScoring,
  candidate: MerchantCandidateForScoring,
): CandidateAgreement {
  const brandScore = usableBrandCandidates.length > 0
    ? Math.max(
      ...usableBrandCandidates.map((b) =>
        diceCoefficient(b, candidate.canonical_name)
      ),
    )
    : 0;

  let placesScore = placesWinner.name
    ? diceCoefficient(placesWinner.name, candidate.canonical_name)
    : 0;

  const agree = typesAgree(candidate.typical_place_types, placesWinner.types);
  if (agree === false) placesScore *= TYPE_AGREEMENT_MISMATCH_PENALTY;

  const qualifies = brandScore >= BRAND_AGREEMENT_THRESHOLD &&
    placesScore >= PLACES_AGREEMENT_THRESHOLD;

  return {
    candidate,
    brandScore,
    placesScore,
    qualifies,
    combinedScore: Math.min(brandScore, placesScore),
  };
}

/**
 * Decides whether a receipt's Places-confirmed location should attach to an
 * existing merchant, or whether a new merchant should be created — using
 * only the brand candidates from `deriveBrandCandidates`, the Places
 * winner's display name/types, and an already-bounded list of merchant
 * candidates (retrieval itself is out of scope). Never throws.
 *
 * Attachment requires BOTH signals to independently agree on the *same*
 * candidate: the brand-candidate text must score above
 * `BRAND_AGREEMENT_THRESHOLD` against that candidate's `canonical_name`,
 * AND the Places winner's name must independently score above
 * `PLACES_AGREEMENT_THRESHOLD` against it (with a type-agreement bonus/
 * penalty folded into the Places-side score — see
 * `TYPE_AGREEMENT_MISMATCH_PENALTY`). Fuzzy text similarity alone, or a
 * missing Places winner, never results in an attach.
 */
export function decideMerchantResolution(
  brandCandidates: string[] | null | undefined,
  placesWinner: PlacesWinnerForScoring | null | undefined,
  merchantCandidates: MerchantCandidateForScoring[] | null | undefined,
): MerchantResolutionDecision {
  const candidates = Array.isArray(brandCandidates) ? brandCandidates : [];
  const usableBrandCandidates = candidates.filter((c) =>
    typeof c === "string" && isUsableMerchantText(c)
  );
  const topBrandCandidate = usableBrandCandidates[0] ?? candidates[0] ?? null;

  if (usableBrandCandidates.length === 0) {
    return {
      action: "create_new",
      merchantId: null,
      canonicalNameForNew: topBrandCandidate,
      confidence: 0,
      reason: topBrandCandidate ? "brand_candidate_low_signal" : "no_brand_candidate",
      brandCandidate: topBrandCandidate,
    };
  }

  const candidateList = Array.isArray(merchantCandidates)
    ? merchantCandidates
    : [];
  if (candidateList.length === 0) {
    return {
      action: "create_new",
      merchantId: null,
      canonicalNameForNew: topBrandCandidate,
      confidence: 0,
      reason: "no_merchant_candidates",
      brandCandidate: topBrandCandidate,
    };
  }

  if (!placesWinner?.name) {
    return {
      action: "create_new",
      merchantId: null,
      canonicalNameForNew: topBrandCandidate,
      confidence: 0,
      reason: "no_places_winner",
      brandCandidate: topBrandCandidate,
    };
  }

  const agreements = candidateList
    .map((c) => scoreCandidateAgreement(usableBrandCandidates, placesWinner, c))
    .filter((a) => a.qualifies)
    .sort((a, b) => b.combinedScore - a.combinedScore);

  if (agreements.length === 0) {
    return {
      action: "create_new",
      merchantId: null,
      canonicalNameForNew: topBrandCandidate,
      confidence: 0,
      reason: "no_candidate_agreement",
      brandCandidate: topBrandCandidate,
    };
  }

  const winner = agreements[0];
  return {
    action: "attach_existing",
    merchantId: winner.candidate.id,
    canonicalNameForNew: null,
    confidence: winner.combinedScore,
    reason: "brand_and_places_agree",
    brandCandidate: topBrandCandidate,
  };
}
