// Deno.test unit tests for the pure helpers in merchant_resolution.ts. No
// network or DB access — this module only derives brand-candidate strings
// from an already-validated LLM understanding and scores an
// already-retrieved bounded merchant-candidate list; retrieval (pg_trgm) and
// persistence (the reconciliation RPC) belong to later rollout tasks and are
// exercised by database/Edge integration tests instead, mirroring the
// precedent set by place_matching.test.ts.
//
// Run with: deno test supabase/functions/_shared/merchant_resolution.test.ts

import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  BRAND_AGREEMENT_THRESHOLD,
  decideMerchantResolution,
  deriveBrandCandidates,
  type MerchantCandidateForScoring,
  PLACES_AGREEMENT_THRESHOLD,
} from "./merchant_resolution.ts";

// ---------------------------------------------------------------------------
// A. deriveBrandCandidates
// ---------------------------------------------------------------------------

Deno.test("deriveBrandCandidates: branch-bearing merchant_name with a generic search-query variant", () => {
  // The McDonald's Pavilion KL / McDonald's pattern used throughout
  // receipt_understanding.test.ts and place_matching.test.ts fixtures.
  const candidates = deriveBrandCandidates({
    merchant_name: "McDonald's Pavilion KL",
    merchant_search_queries: ["McDonald's Pavilion KL", "McDonald's"],
    location_clues: ["Pavilion KL"],
  });
  assertEquals(candidates[0], "McDonald's");
});

Deno.test("deriveBrandCandidates: falls back to stripping location_clues out of merchant_name when no generic query exists", () => {
  const candidates = deriveBrandCandidates({
    merchant_name: "Watsons Sunway Pyramid",
    merchant_search_queries: [],
    location_clues: ["Sunway Pyramid"],
  });
  assertEquals(candidates[0], "Watsons");
});

Deno.test("deriveBrandCandidates: falls back to merchant_name unchanged when there is nothing to strip", () => {
  const candidates = deriveBrandCandidates({
    merchant_name: "Restoran Anwar Maju",
    merchant_search_queries: [],
    location_clues: [],
  });
  assertEquals(candidates, ["Restoran Anwar Maju"]);
});

Deno.test("deriveBrandCandidates: strips a trailing Malaysian legal-entity suffix", () => {
  const candidates = deriveBrandCandidates({
    merchant_name: "Restoran Anwar Maju Sdn Bhd",
    merchant_search_queries: [],
    location_clues: [],
  });
  assertEquals(candidates[0], "Restoran Anwar Maju");
});

Deno.test("deriveBrandCandidates: strips a bare 'Enterprise' suffix", () => {
  const candidates = deriveBrandCandidates({
    merchant_name: "Kedai Runcit Sri Jaya Enterprise",
    merchant_search_queries: [],
    location_clues: [],
  });
  assertEquals(candidates[0], "Kedai Runcit Sri Jaya");
});

Deno.test("deriveBrandCandidates: does not use a location-clue-stripped remainder that is too short to be a usable brand", () => {
  // Stripping "Kedai" from "Kedai" leaves nothing usable — must fall back to
  // the unchanged merchant_name rather than an empty/trivial string.
  const candidates = deriveBrandCandidates({
    merchant_name: "Kedai",
    merchant_search_queries: [],
    location_clues: ["Kedai"],
  });
  assertEquals(candidates, ["Kedai"]);
});

Deno.test("deriveBrandCandidates: returns [] for a null merchant_name", () => {
  assertEquals(
    deriveBrandCandidates({
      merchant_name: null,
      merchant_search_queries: ["Some Query"],
      location_clues: [],
    }),
    [],
  );
});

Deno.test("deriveBrandCandidates: returns [] for entirely empty input", () => {
  assertEquals(
    deriveBrandCandidates({
      merchant_name: null,
      merchant_search_queries: [],
      location_clues: [],
    }),
    [],
  );
});

Deno.test("deriveBrandCandidates: never throws on garbage input shapes", () => {
  // deno-lint-ignore no-explicit-any
  const garbage: any = { merchant_name: "  ", merchant_search_queries: null, location_clues: undefined };
  assertEquals(deriveBrandCandidates(garbage), []);
});

Deno.test("deriveBrandCandidates: deduplicates candidates that normalize the same", () => {
  const candidates = deriveBrandCandidates({
    merchant_name: "Starbucks 1 Utama",
    merchant_search_queries: ["STARBUCKS", "Starbucks!!"],
    location_clues: ["1 Utama"],
  });
  // "STARBUCKS" and "Starbucks!!" normalize identically, and the
  // location-clue-stripped merchant_name fallback also normalizes the same
  // — only one "Starbucks" entry should survive.
  const normalizedSet = new Set(
    candidates.map((c: string) => c.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim()),
  );
  assertEquals(normalizedSet.size, candidates.length);
  assertEquals(candidates[0].toLowerCase(), "starbucks");
});

Deno.test("deriveBrandCandidates: ignores a search-query entry equal to merchant_name after clue stripping", () => {
  // If the "generic" query is really just the branch-bearing name again, it
  // must not be preferred over the real stripping fallback.
  const candidates = deriveBrandCandidates({
    merchant_name: "Tealive Sunway Velocity",
    merchant_search_queries: ["Tealive Sunway Velocity"],
    location_clues: ["Sunway Velocity"],
  });
  assertEquals(candidates[0], "Tealive");
});

// ---------------------------------------------------------------------------
// B. decideMerchantResolution
// ---------------------------------------------------------------------------

function candidate(
  id: string,
  canonical_name: string,
  typical_place_types?: string[],
): MerchantCandidateForScoring {
  return { id, canonical_name, typical_place_types };
}

Deno.test("decideMerchantResolution: attaches when brand and Places both independently agree", () => {
  const decision = decideMerchantResolution(
    ["McDonald's"],
    { name: "McDonald's", types: ["fast_food_restaurant"] },
    [candidate("m1", "McDonald's", ["fast_food_restaurant"])],
  );
  assertEquals(decision.action, "attach_existing");
  assertEquals(decision.merchantId, "m1");
  assertEquals(decision.reason, "brand_and_places_agree");
  assert(decision.confidence >= BRAND_AGREEMENT_THRESHOLD);
});

Deno.test("decideMerchantResolution: does not attach on brand-text similarity alone when Places disagrees", () => {
  // Same brand text, but the Places winner is an unrelated business — the
  // receipt-side signal alone must never be enough.
  const decision = decideMerchantResolution(
    ["Restoran Anwar Maju"],
    { name: "Uncle Lim's Noodle House", types: ["restaurant"] },
    [candidate("m1", "Restoran Anwar Maju", ["restaurant"])],
  );
  assertEquals(decision.action, "create_new");
  assertEquals(decision.reason, "no_candidate_agreement");
});

Deno.test("decideMerchantResolution: never attaches when there is no Places winner at all", () => {
  const decision = decideMerchantResolution(
    ["Restoran Anwar Maju"],
    null,
    [candidate("m1", "Restoran Anwar Maju", ["restaurant"])],
  );
  assertEquals(decision.action, "create_new");
  assertEquals(decision.reason, "no_places_winner");
});

Deno.test("decideMerchantResolution: same-name independent stores — only the candidate with genuine Places-side (type) agreement wins", () => {
  // Two unrelated businesses happen to share an identical canonical name in
  // the retrieved candidate set (a real possibility for generic Malaysian
  // shop names). Brand-text score is identical against both, so type
  // agreement with the Places winner is what must disambiguate them —
  // otherwise this module would have to guess and could false-merge.
  const sameName = "Kedai Runcit Sri Jaya";
  const decision = decideMerchantResolution(
    [sameName],
    { name: sameName, types: ["convenience_store"] },
    [
      candidate("wrong-store", sameName, ["hardware_store"]),
      candidate("right-store", sameName, ["convenience_store"]),
    ],
  );
  assertEquals(decision.action, "attach_existing");
  assertEquals(decision.merchantId, "right-store");
});

Deno.test("decideMerchantResolution: OCR-noisy brand text still resolves correctly via diceCoefficient's existing robustness", () => {
  const decision = decideMerchantResolution(
    ["RESTORAN ANWAR MAU"], // OCR-garbled
    { name: "Restoran Anwar Maju", types: ["restaurant"] },
    [candidate("m1", "Restoran Anwar Maju", ["restaurant"])],
  );
  assertEquals(decision.action, "attach_existing");
  assertEquals(decision.merchantId, "m1");
});

Deno.test("decideMerchantResolution: Malaysian legal-suffix brand text still agrees with the unsuffixed canonical name", () => {
  const decision = decideMerchantResolution(
    ["Restoran Anwar Maju"], // as deriveBrandCandidates would have stripped it
    { name: "Restoran Anwar Maju", types: ["restaurant"] },
    [candidate("m1", "Restoran Anwar Maju", ["restaurant"])],
  );
  assertEquals(decision.action, "attach_existing");
});

Deno.test("decideMerchantResolution: a too-short/low-signal brand candidate never qualifies for attachment", () => {
  const decision = decideMerchantResolution(
    ["Ab"], // below the usable-merchant-text floor
    { name: "Ab Mart", types: ["convenience_store"] },
    [candidate("m1", "Ab Mart", ["convenience_store"])],
  );
  assertEquals(decision.action, "create_new");
  assertEquals(decision.reason, "brand_candidate_low_signal");
});

Deno.test("decideMerchantResolution: a too-generic brand candidate resolves to no-match rather than a forced attach", () => {
  const decision = decideMerchantResolution(
    ["Cafe"],
    { name: "Kedai Kopi Cafe", types: ["cafe"] },
    [candidate("m1", "Kedai Kopi Cafe", ["cafe"])],
  );
  assertEquals(decision.action, "create_new");
  assert(
    decision.reason === "no_candidate_agreement" ||
      decision.reason === "brand_candidate_low_signal",
  );
});

Deno.test("decideMerchantResolution: rebrand-style old vs new brand names are treated as textually distinct, never force-merged on name alone", () => {
  // No location/place-id awareness here — even though this might physically
  // be the same unit, the module must not merge without matching
  // Places-side agreement, and a genuine rebrand also won't have matching
  // Places-side agreement against the *old* brand's canonical name.
  const decision = decideMerchantResolution(
    ["Kopi Kenangan"], // new brand name from the current receipt
    { name: "Kopi Kenangan", types: ["cafe"] },
    [candidate("old-brand", "Rasa Sayang Kopitiam", ["cafe"])],
  );
  assertEquals(decision.action, "create_new");
  assertEquals(decision.reason, "no_candidate_agreement");
});

Deno.test("decideMerchantResolution: multiple nearby merchant candidates — the highest-agreement one wins, not the first in list order", () => {
  const decision = decideMerchantResolution(
    ["Starbucks"],
    { name: "Starbucks Coffee", types: ["cafe"] },
    [
      candidate("weak-match", "Starbies Koffee", ["cafe"]),
      candidate("strong-match", "Starbucks", ["cafe"]),
      candidate("another-weak-match", "Star Bucks Café", ["cafe"]),
    ],
  );
  assertEquals(decision.action, "attach_existing");
  assertEquals(decision.merchantId, "strong-match");
});

Deno.test("decideMerchantResolution: creates new with no candidates provided at all", () => {
  const decision = decideMerchantResolution(
    ["Some New Shop"],
    { name: "Some New Shop", types: ["convenience_store"] },
    [],
  );
  assertEquals(decision.action, "create_new");
  assertEquals(decision.canonicalNameForNew, "Some New Shop");
});

Deno.test("decideMerchantResolution: null merchant_name / no brand candidates never throws and creates new with a null canonical name", () => {
  const decision = decideMerchantResolution([], null, []);
  assertEquals(decision.action, "create_new");
  assertEquals(decision.reason, "no_brand_candidate");
  assertEquals(decision.merchantId, null);
  assertEquals(decision.canonicalNameForNew, null);
});

Deno.test("decideMerchantResolution: confidence is always within [0, 1]", () => {
  const decision = decideMerchantResolution(
    ["McDonald's"],
    { name: "McDonald's", types: ["fast_food_restaurant"] },
    [candidate("m1", "McDonald's", ["fast_food_restaurant"])],
  );
  assert(decision.confidence >= 0 && decision.confidence <= 1);
});

Deno.test("decideMerchantResolution: exported thresholds are sane, documented rollout knobs (not magic inline numbers)", () => {
  assert(BRAND_AGREEMENT_THRESHOLD > 0 && BRAND_AGREEMENT_THRESHOLD < 1);
  assert(PLACES_AGREEMENT_THRESHOLD > 0 && PLACES_AGREEMENT_THRESHOLD < 1);
});
