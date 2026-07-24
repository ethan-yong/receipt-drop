// Deno.test unit tests for the pure helpers in place_matching.ts. No network
// or DB access — these only cover logic that's genuinely testable in
// isolation from the full enrich-transaction handler (see docs/api.md and
// memory/bugs.md for what's verified manually instead: alias-table RLS/RPC
// behavior against a live Postgres, mirroring the precedent already set by
// services/leaderboard-api's own test suite for the same kind of
// DB-dependent behavior).
//
// Run with: deno test supabase/functions/_shared/place_matching.test.ts
// (There is no existing Deno test infra or CI wiring in this repo yet — see
// docs/api.md / .claude/commands.md. This is a new testing surface.)

import {
  assert,
  assertAlmostEquals,
  assertEquals,
  assertNotEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  ALIAS_GEOHASH_PRECISION,
  ALIAS_MIN_TRUST_CONFIDENCE,
  buildTextSearchQueries,
  diceCoefficient,
  geohashEncode,
  normalizeForCompare,
  scoreCandidate,
} from "./place_matching.ts";

Deno.test("geohashEncode produces a stable bucket for the same coordinates", () => {
  const a = geohashEncode(3.1390, 101.6869, ALIAS_GEOHASH_PRECISION);
  const b = geohashEncode(3.1390, 101.6869, ALIAS_GEOHASH_PRECISION);
  assertEquals(a, b);
  assertEquals(a.length, ALIAS_GEOHASH_PRECISION);
});

Deno.test("geohashEncode buckets small GPS drift into the same cell", () => {
  // ~5m of drift (typical phone GPS noise) at precision 7 (~150m cells)
  // must still land in the same bucket, or the alias fast-path would never
  // hit on a repeat visit.
  const a = geohashEncode(3.13900, 101.68690, ALIAS_GEOHASH_PRECISION);
  const b = geohashEncode(3.13905, 101.68695, ALIAS_GEOHASH_PRECISION);
  assertEquals(a, b);
});

Deno.test("geohashEncode gives different buckets for genuinely distant points", () => {
  const kl = geohashEncode(3.1390, 101.6869, ALIAS_GEOHASH_PRECISION);
  const penang = geohashEncode(5.4141, 100.3288, ALIAS_GEOHASH_PRECISION);
  assertNotEquals(kl, penang);
});

Deno.test("geohashEncode matches the known reference value for a fixed point", () => {
  // Cross-check against lib/core/utils/place_key.dart's algorithm at a
  // widely-documented reference coordinate (Wikipedia's geohash example,
  // truncated to our precision) — catches a silent divergence between the
  // Dart and TS ports without needing to run the Dart side here.
  const hash = geohashEncode(57.64911, 10.40744, 6);
  assertEquals(hash, "u4pruy");
});

Deno.test("normalizeForCompare is case- and punctuation-insensitive", () => {
  assertEquals(
    normalizeForCompare("Restoran Anwar Maju!"),
    normalizeForCompare("RESTORAN   anwar-maju"),
  );
});

Deno.test("normalizeForCompare collapses whitespace", () => {
  assertEquals(normalizeForCompare("A   B\tC"), "a b c");
});

Deno.test("diceCoefficient scores a close OCR-garbled match highly", () => {
  const score = diceCoefficient("RESTORAN ANWAR MAU", "Restoran Anwar Maju");
  assert(score > 0.85, `expected > 0.85, got ${score}`);
});

Deno.test("diceCoefficient scores unrelated strings low", () => {
  const score = diceCoefficient("RESTORAN ANWAR MAU", "KFC Sunway Pyramid");
  assert(score < 0.3, `expected < 0.3, got ${score}`);
});

Deno.test("buildTextSearchQueries falls back to a single fallback query when candidates are empty", () => {
  assertEquals(buildTextSearchQueries(null, "ROCK CAFE"), ["ROCK CAFE"]);
  assertEquals(buildTextSearchQueries([], "ROCK CAFE"), ["ROCK CAFE"]);
});

Deno.test("buildTextSearchQueries returns [] when there is no fallback text either", () => {
  assertEquals(buildTextSearchQueries(null, ""), []);
});

Deno.test("buildTextSearchQueries takes up to maxQueries ranked candidates", () => {
  const candidates = [
    { text: "RESTORAN ANWAR MAJU", confidence: 0.92, source: "header" },
    { text: "ANWAR MAJU", confidence: 0.82, source: "keyword" },
    { text: "SOME OTHER LINE", confidence: 0.4, source: "position" },
  ];
  const queries = buildTextSearchQueries(candidates, "fallback");
  assertEquals(queries, ["RESTORAN ANWAR MAJU", "ANWAR MAJU"]);
});

Deno.test("buildTextSearchQueries de-duplicates candidates that normalize the same", () => {
  const candidates = [
    { text: "Restoran Anwar Maju", confidence: 0.9, source: "header" },
    { text: "RESTORAN ANWAR MAJU!", confidence: 0.8, source: "keyword" },
    { text: "Backup Line", confidence: 0.5, source: "position" },
  ];
  const queries = buildTextSearchQueries(candidates, "fallback");
  assertEquals(queries, ["Restoran Anwar Maju", "Backup Line"]);
});

Deno.test("scoreCandidate: reliable text weights text similarity heavily", () => {
  // A close text match, slightly farther away, should still beat a poor
  // text match that's closer — this is the "nearby restaurant selection"
  // case: don't let raw proximity override a clearly-correct name match.
  const weights = { textWeight: 0.6, distWeight: 0.4, cap: 0.97 };
  const location = { lat: 3.1390, lng: 101.6869 };

  const goodTextFartherCandidate = {
    name: "Restoran Anwar Maju",
    lat: 3.1395, // ~60m away
    lng: 101.6869,
  };
  const badTextCloserCandidate = {
    name: "Unrelated Shop",
    lat: 3.1390, // ~0m away
    lng: 101.6869,
  };

  const goodScore = scoreCandidate(
    goodTextFartherCandidate,
    ["RESTORAN ANWAR MAU"],
    weights,
    location,
  );
  const badScore = scoreCandidate(
    badTextCloserCandidate,
    ["RESTORAN ANWAR MAU"],
    weights,
    location,
  );

  assert(
    goodScore > badScore,
    `expected close-text candidate (${goodScore}) to beat close-distance-only candidate (${badScore})`,
  );
});

Deno.test("scoreCandidate: poor text leans almost entirely on distance", () => {
  const weights = { textWeight: 0.15, distWeight: 0.85, cap: 0.65 };
  const location = { lat: 3.1390, lng: 101.6869 };

  const near = { name: "Kedai Serbaneka", lat: 3.1390, lng: 101.6869 };
  const far = { name: "Kedai Serbaneka", lat: 3.1450, lng: 101.6950 }; // ~1km+

  const nearScore = scoreCandidate(near, ["Mel"], weights, location);
  const farScore = scoreCandidate(far, ["Mel"], weights, location);

  assert(
    nearScore > farScore,
    `expected nearer candidate (${nearScore}) to score higher than farther one (${farScore})`,
  );
  assert(nearScore <= 0.65, "score must respect the cap");
});

Deno.test("scoreCandidate: uses the best match across multiple query texts", () => {
  const weights = { textWeight: 0.6, distWeight: 0.4, cap: 0.97 };
  const candidate = { name: "Anwar Maju", lat: null, lng: null };

  // A noisy/long query text scores this candidate poorly, but a cleaner
  // second candidate query scores it well — the best of the two must win,
  // not the first one tried.
  const score = scoreCandidate(
    candidate,
    ["RESTORAN ANWAR MAJU SDN BHD JALAN EXAMPLE 123", "ANWAR MAJU"],
    weights,
    null,
  );
  const scoreFromNoisyQueryOnly = scoreCandidate(
    candidate,
    ["RESTORAN ANWAR MAJU SDN BHD JALAN EXAMPLE 123"],
    weights,
    null,
  );

  assert(
    score > scoreFromNoisyQueryOnly,
    `expected best-of-both-queries score (${score}) to beat noisy-query-only score (${scoreFromNoisyQueryOnly})`,
  );
});

Deno.test("scoreCandidate: never scores below the 0.05 floor", () => {
  const weights = { textWeight: 0.6, distWeight: 0.4, cap: 0.97 };
  const candidate = { name: "Completely Unrelated", lat: null, lng: null };
  const score = scoreCandidate(candidate, ["zzz"], weights, null);
  assert(score >= 0.05);
});

Deno.test("scoreCandidate: a candidate with no name scores 0 on text alone", () => {
  const weights = { textWeight: 1, distWeight: 0, cap: 0.97 };
  const candidate = { name: null, lat: null, lng: null };
  const score = scoreCandidate(candidate, ["anything"], weights, null);
  assertAlmostEquals(score, 0.05); // floor, since raw text score is 0
});

// The gating this constant drives (enrich-transaction's alias fast-path
// falling through to Places when a decayed alias hit is below this floor)
// lives in the live Edge Function handler against a real
// lookup_merchant_alias RPC result — too entangled with request/DB state to
// unit test cleanly here, consistent with this file's own header comment
// about DB-dependent behavior being verified manually instead. This test
// only pins the constant itself to the documented, reasoned band between
// lookup_merchant_alias's 0.05 hard decay floor and the ~0.7+ "established"
// alias tier used elsewhere in the same migration.
Deno.test("ALIAS_MIN_TRUST_CONFIDENCE sits between the read-path decay floor (0.05) and the established-alias tier (~0.7)", () => {
  assert(ALIAS_MIN_TRUST_CONFIDENCE > 0.05);
  assert(ALIAS_MIN_TRUST_CONFIDENCE < 0.7);
});
