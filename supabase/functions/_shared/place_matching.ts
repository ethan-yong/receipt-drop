export const SEARCH_RADIUS_METERS = 300;

/** Geohash bucket precision for merchant-alias lookup (~150m x 150m cells —
 * coarser than the map's precision-8 aggregation key, since phone GPS drift
 * (10-50m, worse indoors) would otherwise scatter repeat visits to the same
 * place across different buckets. */
export const ALIAS_GEOHASH_PRECISION = 7;

/** Only cache a merchant alias when the resolution that produced it was
 * confident enough to trust for future scans without a human in the loop. */
export const ALIAS_SAVE_CONFIDENCE_THRESHOLD = 0.85;

/** Normalizes text for both alias-key comparison and Dice-coefficient
 * scoring: lowercase, then collapses every run of punctuation/whitespace
 * (spaces, tabs, hyphens, punctuation, ...) into a single space, so
 * separators are treated as word boundaries rather than deleted outright
 * (deleting them would fuse "anwar-maju" into "anwarmaju" instead of
 * "anwar maju"). */
export function normalizeForCompare(s: string): string {
  return s
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

/** Rejects OCR merchant guesses too short/garbled to trust as a text signal. */
export function isUsableMerchantText(s: string | null | undefined): boolean {
  if (!s) return false;
  return s.replace(/[^a-zA-Z0-9]/g, "").length >= 4;
}

/**
 * Character-bigram Sorensen-Dice coefficient, 0..1. Robust to OCR noise
 * since it doesn't require whole-token/word matches.
 */
export function diceCoefficient(a: string, b: string): number {
  const bigramCounts = (s: string): Map<string, number> => {
    const norm = normalizeForCompare(s);
    const m = new Map<string, number>();
    for (let i = 0; i < norm.length - 1; i++) {
      const bg = norm.slice(i, i + 2);
      m.set(bg, (m.get(bg) ?? 0) + 1);
    }
    return m;
  };
  const ba = bigramCounts(a);
  const bb = bigramCounts(b);
  if (ba.size === 0 || bb.size === 0) return 0;
  let overlap = 0;
  for (const [bg, countA] of ba) {
    const countB = bb.get(bg);
    if (countB) overlap += Math.min(countA, countB);
  }
  const totalA = [...ba.values()].reduce((s, v) => s + v, 0);
  const totalB = [...bb.values()].reduce((s, v) => s + v, 0);
  return (2 * overlap) / (totalA + totalB);
}

export function haversineMeters(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number,
): number {
  const R = 6371000;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

/** Smooth exponential decay: 1.0 at 0m, ~0.37 at 150m, ~0.14 at 300m. */
export function distanceScore(distanceMeters: number): number {
  return Math.exp(-distanceMeters / 150);
}

export const CATEGORY_TO_PLACE_TYPES: Record<string, string[]> = {
  "Food & Drink": [
    "restaurant",
    "cafe",
    "bakery",
    "meal_takeaway",
    "meal_delivery",
    "bar",
    "fast_food_restaurant",
    "coffee_shop",
    "food_court",
  ],
  "Groceries": ["supermarket", "grocery_store", "convenience_store"],
  "Transport": [
    "gas_station",
    "parking",
    "subway_station",
    "train_station",
    "transit_station",
  ],
  "Travel": ["lodging", "airport", "travel_agency"],
  "Shopping": [
    "clothing_store",
    "shopping_mall",
    "department_store",
    "electronics_store",
    "home_goods_store",
    "hardware_store",
  ],
  "Health & Beauty": [
    "pharmacy",
    "drugstore",
    "hospital",
    "doctor",
    "beauty_salon",
  ],
};

export const DEFAULT_NEARBY_TYPES = Array.from(
  new Set(Object.values(CATEGORY_TO_PLACE_TYPES).flat()),
);

const GEOHASH_BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz";

/**
 * Standard geohash base-32 encoding, ported verbatim from
 * `lib/core/utils/place_key.dart`'s `_geohashEncode` (Dart) — the two must
 * stay in sync (same bit-packing order) since a receipt's bucket has to
 * match regardless of which side computes it. If you change one, change the
 * other; this is a known Dart/TS logic-parity risk (see
 * memory/dependency_graph.md).
 */
export function geohashEncode(
  latitude: number,
  longitude: number,
  precision: number,
): string {
  let latMin = -90.0;
  let latMax = 90.0;
  let lonMin = -180.0;
  let lonMax = 180.0;
  const bits = [16, 8, 4, 2, 1];
  let out = "";
  let bit = 0;
  let ch = 0;
  let even = true;

  while (out.length < precision) {
    if (even) {
      const mid = (lonMin + lonMax) / 2;
      if (longitude > mid) {
        ch |= bits[bit];
        lonMin = mid;
      } else {
        lonMax = mid;
      }
    } else {
      const mid = (latMin + latMax) / 2;
      if (latitude > mid) {
        ch |= bits[bit];
        latMin = mid;
      } else {
        latMax = mid;
      }
    }
    even = !even;
    if (bit < 4) {
      bit++;
    } else {
      out += GEOHASH_BASE32[ch];
      bit = 0;
      ch = 0;
    }
  }
  return out;
}

/** A ranked merchant-name guess, as synced from `extractMerchantCandidates`
 * (lib/domain/logic/merchant_extractor.dart) into `transactions.merchant_candidates`. */
export interface MerchantCandidateInput {
  text: string;
  confidence: number;
  source: string;
}

/**
 * Builds up to [maxQueries] distinct Places text-search queries from ranked
 * merchant candidates (highest confidence first), falling back to a single
 * [fallbackText] query when no candidates are available — e.g. rows synced
 * before this column existed, or a merchant extractor that returned nothing.
 */
export function buildTextSearchQueries(
  candidates: MerchantCandidateInput[] | null | undefined,
  fallbackText: string,
  maxQueries = 2,
): string[] {
  if (!candidates || candidates.length === 0) {
    return fallbackText ? [fallbackText] : [];
  }
  const seen = new Set<string>();
  const queries: string[] = [];
  for (const c of candidates) {
    const text = c.text?.trim();
    if (!text) continue;
    const key = normalizeForCompare(text);
    if (seen.has(key)) continue;
    seen.add(key);
    queries.push(text);
    if (queries.length >= maxQueries) break;
  }
  return queries.length > 0 ? queries : fallbackText ? [fallbackText] : [];
}

/** Weights/cap for blending text similarity with distance — how much each
 * signal can be trusted shifts by how reliable the OCR text looks. */
export interface CandidateScoreWeights {
  textWeight: number;
  distWeight: number;
  cap: number;
}

/**
 * Scores a single Places candidate against one or more OCR-derived query
 * texts (the *best* match across them, so a candidate isn't penalized just
 * because it happens to match the shorter/cleaner candidate rather than the
 * longest one) and, when available, distance from the share-time GPS
 * location. Pure — no network/DB access — so it's unit-testable in
 * isolation from the full `enrich-transaction` handler.
 */
export function scoreCandidate(
  candidate: { name: string | null; lat: number | null; lng: number | null },
  queryTexts: string[],
  weights: CandidateScoreWeights,
  location: { lat: number; lng: number } | null,
): number {
  const textScore = candidate.name && queryTexts.length > 0
    ? Math.max(
      ...queryTexts.map((q) => diceCoefficient(q, candidate.name!)),
    )
    : 0;
  const distScore =
    location && candidate.lat != null && candidate.lng != null
      ? distanceScore(
        haversineMeters(location.lat, location.lng, candidate.lat, candidate.lng),
      )
      : null;

  const raw = distScore === null
    ? textScore
    : weights.textWeight * textScore + weights.distWeight * distScore;

  return Math.max(0.05, Math.min(weights.cap, raw));
}
