import { DEFAULT_NEARBY_TYPES, normalizeForCompare } from "./place_matching.ts";

/** Hard ceiling on the ocr-api /understand round-trip — enrich-transaction is
 * invoked fire-and-forget from the sync worker, but edge functions still have
 * a wall-clock budget and the user may be watching the place fill in. Well
 * above ocr-api's own LLM_TIMEOUT_SECONDS (25s) so a slow-but-successful LLM
 * call there isn't cut off here first. */
export const UNDERSTAND_TIMEOUT_MS = 30_000;

export const MAX_MERCHANT_SEARCH_QUERIES = 3;

/** Mirrors ocr-api's MAX_LINE_ITEMS (app/receipt_understanding.py). */
export const MAX_LINE_ITEMS = 40;

/** Multiplier applied to a Places candidate whose types share nothing with
 * the LLM's expected place types — enough to sink a same-mall Nike Store
 * below any plausible food candidate without hard-filtering results whose
 * types Google simply didn't return. */
export const TYPE_MISMATCH_PENALTY = 0.6;

/** The closed category vocabulary the LLM is prompted to answer within.
 * Anything outside it is treated as "the model went off-script" and nulled. */
export const VENDOR_CATEGORIES = [
  "food_and_drink",
  "groceries",
  "transport",
  "travel",
  "shopping",
  "health_beauty",
  "entertainment",
  "services",
  "other",
] as const;

export type VendorCategory = (typeof VENDOR_CATEGORIES)[number];

/** Server-side vendor-category → Places v1 types, used when the LLM returns
 * an empty or fully-invalid `google_place_types` but a valid category.
 * Deliberately separate from place_matching.ts's CATEGORY_TO_PLACE_TYPES,
 * which is keyed on the app's display categories ("Food & Drink") and still
 * serves places-proxy. */
export const VENDOR_CATEGORY_TO_PLACE_TYPES: Record<string, string[]> = {
  food_and_drink: [
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
  groceries: ["supermarket", "grocery_store", "convenience_store", "market"],
  transport: [
    "gas_station",
    "parking",
    "subway_station",
    "train_station",
    "transit_station",
    "taxi_stand",
  ],
  travel: ["lodging", "hotel", "airport", "travel_agency"],
  shopping: [
    "clothing_store",
    "shopping_mall",
    "department_store",
    "electronics_store",
    "home_goods_store",
    "hardware_store",
    "shoe_store",
    "book_store",
    "pet_store",
    "sporting_goods_store",
    "jewelry_store",
    "gift_shop",
    "florist",
  ],
  health_beauty: [
    "pharmacy",
    "drugstore",
    "hospital",
    "doctor",
    "dental_clinic",
    "beauty_salon",
    "hair_salon",
    "spa",
    "gym",
  ],
  entertainment: [
    "movie_theater",
    "amusement_park",
    "bowling_alley",
    "night_club",
    "tourist_attraction",
    "karaoke",
  ],
  services: [
    "laundry",
    "post_office",
    "bank",
    "atm",
    "car_repair",
    "car_wash",
    "veterinary_care",
    "insurance_agency",
  ],
  other: [],
};

/** Every Places v1 (Table A) type the LLM is allowed to return. Types
 * outside this set are dropped during validation (not fatal) — LLMs happily
 * invent plausible-sounding types like "hypermarket". */
export const ALLOWED_PLACE_TYPES: Set<string> = new Set([
  ...DEFAULT_NEARBY_TYPES,
  ...Object.values(VENDOR_CATEGORY_TO_PLACE_TYPES).flat(),
  "ice_cream_shop",
  "dessert_shop",
  "juice_shop",
  "tea_house",
  "steak_house",
  "pizza_restaurant",
  "hamburger_restaurant",
  "seafood_restaurant",
  "vegetarian_restaurant",
  "asian_restaurant",
  "chinese_restaurant",
  "indian_restaurant",
  "indonesian_restaurant",
  "japanese_restaurant",
  "korean_restaurant",
  "malay_restaurant" /* not in Table A today, harmless if unmatched */,
  "thai_restaurant",
  "vietnamese_restaurant",
  "liquor_store",
  "butcher_shop",
  "cell_phone_store",
  "furniture_store",
  "bicycle_store",
  "auto_parts_store",
  "car_dealer",
  "skin_care_clinic",
  "nail_salon",
  "physiotherapist",
  "optician",
  "barber_shop",
]);

/** Human search word per category for the address-only query path ("no
 * readable merchant name, but the receipt clearly says Jalan SS15"). */
const VENDOR_CATEGORY_QUERY_HINTS: Record<string, string> = {
  food_and_drink: "restaurant",
  groceries: "supermarket",
  transport: "petrol station",
  travel: "hotel",
  shopping: "shop",
  health_beauty: "pharmacy",
  entertainment: "cinema",
  services: "shop",
  other: "shop",
};

export interface ReceiptUnderstandingConfidence {
  merchant: number;
  address: number;
  category: number;
  line_items: number;
}

/** One purchased item reconstructed from noisy OCR text — see ocr-api's
 * ReceiptLineItemUnderstanding (app/receipt_understanding.py). */
export interface ReceiptUnderstandingLineItem {
  name: string;
  price: number | null;
  quantity: number | null;
}

/** The validated, structured interpretation of one receipt's OCR text, as
 * produced by the LLM and consumed by the Google Places search in
 * enrich-transaction. Field names deliberately match the LLM's JSON keys so
 * the object can be persisted verbatim into transactions.llm_understanding. */
export interface ReceiptUnderstanding {
  merchant_name: string | null;
  merchant_search_queries: string[];
  address_text: string | null;
  location_clues: string[];
  vendor_category: string | null;
  google_place_types: string[];
  line_items: ReceiptUnderstandingLineItem[];
  confidence: ReceiptUnderstandingConfidence;
  // Skill routing — stamped by call_receipt_understanding, not the LLM prompt.
  receipt_type?: string | null;
  // Skill-specific optional fields (payment, grocery, transport skills).
  transaction_date?: string | null;
  amount?: number | null;
  payment_method?: string | null;
  transaction_id?: string | null;
  booking_reference?: string | null;
  origin?: string | null;
  destination?: string | null;
}

/**
 * Pulls the JSON object out of a raw LLM completion. Defensive against
 * chatty models even when `response_format: json_object` was requested:
 * strips <think>…</think> reasoning blocks and markdown code fences, then
 * slices from the first "{" to the last "}".
 */
export function extractJsonObject(raw: string): string | null {
  let s = raw.replace(/<think>[\s\S]*?<\/think>/gi, "");
  const fence = s.match(/```(?:json)?\s*([\s\S]*?)```/i);
  if (fence) s = fence[1];
  const start = s.indexOf("{");
  const end = s.lastIndexOf("}");
  if (start === -1 || end === -1 || end <= start) return null;
  return s.slice(start, end + 1);
}

function asTrimmedStringOrNull(v: unknown): string | null {
  if (typeof v !== "string") return null;
  const t = v.trim();
  return t.length > 0 ? t : null;
}

function asStringArray(v: unknown): string[] {
  if (!Array.isArray(v)) return [];
  return v
    .map((item) => (typeof item === "string" ? item.trim() : ""))
    .filter((s) => s.length > 0);
}

function clamp01(v: unknown): number {
  const n = typeof v === "number" ? v : Number(v);
  if (!Number.isFinite(n)) return 0;
  return Math.max(0, Math.min(1, n));
}

function asPositiveNumberOrNull(v: unknown): number | null {
  if (v === null || v === undefined || typeof v === "boolean") return null;
  const n = typeof v === "number" ? v : Number(v);
  if (!Number.isFinite(n) || n < 0) return null;
  return n;
}

/** Coerces the LLM's raw `line_items` array, dropping any entry with no
 * usable name — same "hint, not authority" stance as every other field
 * here. Mirrors ocr-api's `_as_line_items` (app/receipt_understanding.py). */
function asLineItems(v: unknown): ReceiptUnderstandingLineItem[] {
  if (!Array.isArray(v)) return [];
  const items: ReceiptUnderstandingLineItem[] = [];
  for (const entry of v) {
    if (entry === null || typeof entry !== "object" || Array.isArray(entry)) {
      continue;
    }
    const obj = entry as Record<string, unknown>;
    const name = asTrimmedStringOrNull(obj.name);
    if (name === null) continue;
    items.push({
      name,
      price: asPositiveNumberOrNull(obj.price),
      quantity: asPositiveNumberOrNull(obj.quantity),
    });
    if (items.length >= MAX_LINE_ITEMS) break;
  }
  return items;
}

/**
 * Parses + validates a raw LLM completion into a [ReceiptUnderstanding].
 * Every field is coerced defensively (wrong types dropped, out-of-range
 * confidences clamped, off-vocabulary categories/place-types discarded,
 * queries deduped and capped) — the LLM's output is a hint, this function is
 * the authority. Returns null only when there is no parseable JSON object at
 * all, or when the result carries nothing actionable (no merchant name, no
 * queries, no address, no location clues).
 */
export function parseReceiptUnderstanding(
  raw: string,
): ReceiptUnderstanding | null {
  const jsonText = extractJsonObject(raw);
  if (jsonText === null) return null;

  let parsed: unknown;
  try {
    parsed = JSON.parse(jsonText);
  } catch {
    return null;
  }
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    return null;
  }
  const obj = parsed as Record<string, unknown>;

  const merchantName = asTrimmedStringOrNull(obj.merchant_name);

  const seenQueries = new Set<string>();
  const queries: string[] = [];
  for (const q of asStringArray(obj.merchant_search_queries)) {
    const key = normalizeForCompare(q);
    if (key.length === 0 || seenQueries.has(key)) continue;
    seenQueries.add(key);
    queries.push(q);
    if (queries.length >= MAX_MERCHANT_SEARCH_QUERIES) break;
  }

  const rawCategory = asTrimmedStringOrNull(obj.vendor_category)
    ?.toLowerCase();
  const vendorCategory =
    rawCategory && (VENDOR_CATEGORIES as readonly string[]).includes(rawCategory)
      ? rawCategory
      : null;

  const placeTypes = Array.from(
    new Set(
      asStringArray(obj.google_place_types)
        .map((t) => t.toLowerCase().replace(/\s+/g, "_"))
        .filter((t) => ALLOWED_PLACE_TYPES.has(t)),
    ),
  );

  const confidenceObj =
    obj.confidence !== null && typeof obj.confidence === "object" &&
      !Array.isArray(obj.confidence)
      ? obj.confidence as Record<string, unknown>
      : {};

  const lineItems = asLineItems(obj.line_items);

  // Skill-specific optional fields — defensive coercion, wrong types → null.
  const receiptType = asTrimmedStringOrNull(obj.receipt_type);
  const transactionDate = asTrimmedStringOrNull(obj.transaction_date);
  const amount = asPositiveNumberOrNull(obj.amount);
  const paymentMethod = asTrimmedStringOrNull(obj.payment_method);
  const transactionId = asTrimmedStringOrNull(obj.transaction_id);
  const bookingReference = asTrimmedStringOrNull(obj.booking_reference);
  const origin = asTrimmedStringOrNull(obj.origin);
  const destination = asTrimmedStringOrNull(obj.destination);

  const understanding: ReceiptUnderstanding = {
    merchant_name: merchantName,
    merchant_search_queries: queries,
    address_text: asTrimmedStringOrNull(obj.address_text),
    location_clues: asStringArray(obj.location_clues),
    vendor_category: vendorCategory,
    google_place_types: placeTypes,
    line_items: lineItems,
    confidence: {
      merchant: clamp01(confidenceObj.merchant),
      address: clamp01(confidenceObj.address),
      category: clamp01(confidenceObj.category),
      line_items: clamp01(confidenceObj.line_items),
    },
    ...(receiptType !== null && { receipt_type: receiptType }),
    ...(transactionDate !== null && { transaction_date: transactionDate }),
    ...(amount !== null && { amount }),
    ...(paymentMethod !== null && { payment_method: paymentMethod }),
    ...(transactionId !== null && { transaction_id: transactionId }),
    ...(bookingReference !== null && { booking_reference: bookingReference }),
    ...(origin !== null && { origin }),
    ...(destination !== null && { destination }),
  };

  const actionable = understanding.merchant_name !== null ||
    understanding.merchant_search_queries.length > 0 ||
    understanding.address_text !== null ||
    understanding.location_clues.length > 0 ||
    understanding.line_items.length > 0 ||
    understanding.amount != null ||
    understanding.transaction_id != null ||
    understanding.booking_reference != null;
  return actionable ? understanding : null;
}

/**
 * Builds the Places text-search query list from the LLM's understanding:
 * the merchant search queries in order (falling back to merchant_name when
 * the model returned a name but no queries), plus one location-augmented
 * variant ("Starbucks 1 Utama") when an area clue exists — mall vendors
 * disambiguate far better with the mall in the query. When no merchant text
 * exists at all but an address does, emits a single category-hint + address
 * query so the receipt can still resolve to a nearby vendor of the right
 * kind.
 */
export function buildLlmTextQueries(
  u: ReceiptUnderstanding,
  maxQueries = MAX_MERCHANT_SEARCH_QUERIES,
): string[] {
  const seen = new Set<string>();
  const queries: string[] = [];
  const push = (q: string) => {
    const text = q.trim();
    if (!text) return;
    const key = normalizeForCompare(text);
    if (key.length === 0 || seen.has(key)) return;
    seen.add(key);
    queries.push(text);
  };

  const merchantQueries = u.merchant_search_queries.length > 0
    ? u.merchant_search_queries
    : u.merchant_name
    ? [u.merchant_name]
    : [];
  for (const q of merchantQueries) push(q);

  if (queries.length > 0) {
    // One location-augmented variant of the top query, unless the clue is
    // already part of it (the LLM often bakes the mall into query #1).
    const clue = u.location_clues[0] ?? u.address_text;
    if (clue) {
      const top = queries[0];
      const clueKey = normalizeForCompare(clue);
      if (
        clueKey.length > 0 && !normalizeForCompare(top).includes(clueKey)
      ) {
        push(`${top} ${clue.trim()}`);
      }
    }
  } else {
    // Missing-merchant path: category hint + strongest location signal.
    const target = u.address_text ?? u.location_clues.join(" ");
    if (target.trim().length > 0) {
      const hint = (u.vendor_category &&
        VENDOR_CATEGORY_QUERY_HINTS[u.vendor_category]) ?? "shop";
      push(`${hint} ${target.trim()}`);
    }
  }

  return queries.slice(0, maxQueries);
}

/** Nearby-search includedTypes: the LLM's own validated place types, else
 * the category's default set, else the global default union. */
export function resolveIncludedTypes(u: ReceiptUnderstanding): string[] {
  if (u.google_place_types.length > 0) return u.google_place_types;
  if (u.vendor_category) {
    const fromCategory = VENDOR_CATEGORY_TO_PLACE_TYPES[u.vendor_category];
    if (fromCategory && fromCategory.length > 0) return fromCategory;
  }
  return DEFAULT_NEARBY_TYPES;
}

/**
 * Penalizes a scored Places candidate whose reported types share nothing
 * with the LLM's expected types (a food receipt should not resolve to a Nike
 * Store two doors down). Neutral when either side has no type information —
 * text-search results without a populated types field must not be punished
 * for Google's omission.
 */
export function adjustScoreForTypeMatch(
  score: number,
  candidateTypes: string[] | null,
  expectedTypes: string[],
): number {
  if (!candidateTypes || candidateTypes.length === 0) return score;
  if (expectedTypes.length === 0) return score;
  const expected = new Set(expectedTypes);
  const overlaps = candidateTypes.some((t) => expected.has(t));
  return overlaps ? score : score * TYPE_MISMATCH_PENALTY;
}

export interface OcrApiUnderstandingConfig {
  /** Same base URL ocr-proxy forwards OCR requests to — the LLM call now
   * lives in services/ocr-api itself (POST /understand), not a direct call
   * to the vLLM gateway from this edge function. See docs/decisions.md. */
  ocrServiceUrl: string;
  ocrServiceSecret: string;
}

export type ReceiptUnderstandingCallResult =
  | { ok: true; understanding: ReceiptUnderstanding; raw: string; latencyMs: number }
  | { ok: false; error: string; raw: string | null; latencyMs: number };

/**
 * Calls services/ocr-api's `POST /understand` (which itself calls the LLM
 * gateway and validates the response) and re-validates whatever comes back
 * through [parseReceiptUnderstanding] as a second line of defense — cheap,
 * and guards against a version-skew or malformed response between the two
 * services. No fallback: during the testing phase every enrichment must
 * either go through the LLM or fail visibly (timeout, non-2xx, unparseable
 * content all return an error result with no retry).
 */
export async function callReceiptUnderstanding(
  cfg: OcrApiUnderstandingConfig,
  ocrText: string,
  fetchFn: typeof fetch = fetch,
): Promise<ReceiptUnderstandingCallResult> {
  const startedAt = Date.now();
  const elapsed = () => Date.now() - startedAt;
  const url = `${cfg.ocrServiceUrl.replace(/\/+$/, "")}/understand`;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), UNDERSTAND_TIMEOUT_MS);
  let resp: Response;
  try {
    resp = await fetchFn(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-OCR-Secret": cfg.ocrServiceSecret,
      },
      body: JSON.stringify({ ocr_text: ocrText }),
      signal: controller.signal,
    });
  } catch (e) {
    const aborted = e instanceof DOMException && e.name === "AbortError";
    return {
      ok: false,
      error: aborted ? "llm_timeout" : `llm_fetch_failed: ${String(e)}`,
      raw: null,
      latencyMs: elapsed(),
    };
  } finally {
    clearTimeout(timer);
  }

  if (!resp.ok) {
    let bodyText: string | null = null;
    try {
      bodyText = (await resp.text()).slice(0, 500);
    } catch {
      // response body unavailable — status alone is enough context
    }
    return {
      ok: false,
      error: `llm_http_${resp.status}`,
      raw: bodyText,
      latencyMs: elapsed(),
    };
  }

  let raw: string;
  try {
    raw = JSON.stringify(await resp.json());
  } catch {
    return {
      ok: false,
      error: "llm_invalid_response_json",
      raw: null,
      latencyMs: elapsed(),
    };
  }

  const understanding = parseReceiptUnderstanding(raw);
  if (understanding === null) {
    return {
      ok: false,
      error: "llm_unparseable_content",
      raw: raw.slice(0, 2000),
      latencyMs: elapsed(),
    };
  }

  return { ok: true, understanding, raw, latencyMs: elapsed() };
}
