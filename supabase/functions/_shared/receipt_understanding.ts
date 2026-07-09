import { DEFAULT_NEARBY_TYPES, normalizeForCompare } from "./place_matching.ts";

/** Hard ceiling on the LLM round-trip — enrich-transaction is invoked
 * fire-and-forget from the sync worker, but edge functions still have a
 * wall-clock budget and the user may be watching the place fill in. */
export const LLM_TIMEOUT_MS = 25_000;

/** Receipt OCR is normally 0.5-3 KB; anything past this is almost always
 * OCR noise (long itemized invoices already carry the merchant in the
 * header), so cap the prompt rather than pay for the tokens. */
export const MAX_OCR_PROMPT_CHARS = 6_000;

export const LLM_MAX_TOKENS = 700;

export const MAX_MERCHANT_SEARCH_QUERIES = 3;

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
  confidence: ReceiptUnderstandingConfidence;
}

const SYSTEM_PROMPT =
  `You are a receipt-understanding engine for Malaysian receipts. The input is raw OCR text from ONE receipt — a mix of Malay and English, often with OCR errors (dropped letters, wrong characters, merged words).

Respond with ONE JSON object and nothing else — no markdown, no explanation — with exactly these keys:

"merchant_name" (string or null): the business name printed on the receipt, with obvious OCR spelling errors corrected (e.g. "RESTORAN ANWAR MAU" -> "Restoran Anwar Maju") ONLY when you are confident of the intended name, normalized to Title Case. Keep legal suffixes (Sdn Bhd, Enterprise) here if printed. NEVER a phone number, receipt/invoice number, tax/SST/GST/ROC registration ID, cashier name, or slogan. null if no business name is readable.

"merchant_search_queries" (array of 1-3 strings, most specific first): variants of the merchant name suitable for a Google Places text search — strip legal suffixes (Sdn Bhd, Trading, Enterprise), branch codes, and store numbers. Empty array if merchant_name is null.

"address_text" (string or null): the vendor's street address as printed on the receipt, cleaned up, or null if none is present. Never the customer's address.

"location_clues" (array of strings): short area tokens found on the receipt that help locate the vendor — neighbourhood (SS2, USJ 10), mall (Pavilion KL, 1 Utama), city (Petaling Jaya, Kuala Lumpur). Empty array if none.

"vendor_category" (string): exactly one of food_and_drink, groceries, transport, travel, shopping, health_beauty, entertainment, services, other. Infer from the merchant name AND the purchased line items — e.g. shampoo + milk + bread means groceries even if the shop name is unreadable.

"google_place_types" (array of 1-4 strings): Google Places API place types matching this vendor, e.g. restaurant, cafe, bakery, meal_takeaway, fast_food_restaurant, coffee_shop, supermarket, convenience_store, pharmacy, gas_station, clothing_store, hair_salon, gym.

"confidence" (object): {"merchant": 0-1, "address": 0-1, "category": 0-1} — your confidence in each extraction.

If the merchant name is unreadable but an address or line items are present, set merchant_name to null with a low merchant confidence and still fill in the address, location clues, and category.`;

export interface ChatMessage {
  role: "system" | "user";
  content: string;
}

export function buildReceiptUnderstandingMessages(
  ocrText: string,
): ChatMessage[] {
  const truncated = ocrText.length > MAX_OCR_PROMPT_CHARS
    ? ocrText.slice(0, MAX_OCR_PROMPT_CHARS)
    : ocrText;
  return [
    { role: "system", content: SYSTEM_PROMPT },
    { role: "user", content: truncated },
  ];
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

  const understanding: ReceiptUnderstanding = {
    merchant_name: merchantName,
    merchant_search_queries: queries,
    address_text: asTrimmedStringOrNull(obj.address_text),
    location_clues: asStringArray(obj.location_clues),
    vendor_category: vendorCategory,
    google_place_types: placeTypes,
    confidence: {
      merchant: clamp01(confidenceObj.merchant),
      address: clamp01(confidenceObj.address),
      category: clamp01(confidenceObj.category),
    },
  };

  const actionable = understanding.merchant_name !== null ||
    understanding.merchant_search_queries.length > 0 ||
    understanding.address_text !== null ||
    understanding.location_clues.length > 0;
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

export interface LlmGatewayConfig {
  /** Gateway base URL, with or without a trailing /v1. */
  baseUrl: string;
  apiKey: string | null;
  modelName: string;
  reasoningEffort?: string | null;
}

/** Mirrors scripts/inspect_llm_endpoint.py's _normalize_urls: the gateway
 * base may be configured with or without /v1. */
export function chatCompletionsUrl(baseUrl: string): string {
  const base = baseUrl.replace(/\/+$/, "");
  const apiBase = base.endsWith("/v1") ? base : `${base}/v1`;
  return `${apiBase}/chat/completions`;
}

export type ReceiptUnderstandingCallResult =
  | {
    ok: true;
    understanding: ReceiptUnderstanding;
    raw: string;
    model: string;
    latencyMs: number;
  }
  | { ok: false; error: string; raw: string | null; latencyMs: number };

/**
 * Calls the OpenAI-compatible gateway and returns a validated
 * [ReceiptUnderstanding]. `response_format: json_object` is sent as a hint
 * (with one retry without it on HTTP 400, since some LiteLLM/vLLM backends
 * reject the parameter); [parseReceiptUnderstanding] is the authority. Any
 * other failure — timeout, non-2xx, unparseable content — returns an error
 * result with no retry: during the testing phase every enrichment must
 * either go through the LLM or fail visibly.
 */
export async function callReceiptUnderstanding(
  cfg: LlmGatewayConfig,
  ocrText: string,
  fetchFn: typeof fetch = fetch,
): Promise<ReceiptUnderstandingCallResult> {
  const startedAt = Date.now();
  const elapsed = () => Date.now() - startedAt;
  const messages = buildReceiptUnderstandingMessages(ocrText);

  const buildBody = (withResponseFormat: boolean): string => {
    const body: Record<string, unknown> = {
      model: cfg.modelName,
      messages,
      temperature: 0,
      max_tokens: LLM_MAX_TOKENS,
    };
    if (withResponseFormat) {
      body.response_format = { type: "json_object" };
    }
    if (cfg.reasoningEffort) {
      body.reasoning_effort = cfg.reasoningEffort;
    }
    return JSON.stringify(body);
  };

  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };
  if (cfg.apiKey) headers["Authorization"] = `Bearer ${cfg.apiKey}`;

  const url = chatCompletionsUrl(cfg.baseUrl);

  const attempt = async (
    withResponseFormat: boolean,
  ): Promise<Response> => {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), LLM_TIMEOUT_MS);
    try {
      return await fetchFn(url, {
        method: "POST",
        headers,
        body: buildBody(withResponseFormat),
        signal: controller.signal,
      });
    } finally {
      clearTimeout(timer);
    }
  };

  let resp: Response;
  try {
    resp = await attempt(true);
    if (resp.status === 400) {
      // Some gateways reject response_format outright — one narrow retry
      // without it; the manual parser downstream copes with prose-wrapped
      // JSON anyway.
      resp = await attempt(false);
    }
  } catch (e) {
    const aborted = e instanceof DOMException && e.name === "AbortError";
    return {
      ok: false,
      error: aborted ? "llm_timeout" : `llm_fetch_failed: ${String(e)}`,
      raw: null,
      latencyMs: elapsed(),
    };
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

  let content: string;
  let model: string;
  try {
    const json = await resp.json() as {
      model?: string;
      choices?: { message?: { content?: string } }[];
    };
    content = json.choices?.[0]?.message?.content ?? "";
    model = json.model ?? cfg.modelName;
  } catch {
    return {
      ok: false,
      error: "llm_invalid_response_json",
      raw: null,
      latencyMs: elapsed(),
    };
  }

  const understanding = parseReceiptUnderstanding(content);
  if (understanding === null) {
    return {
      ok: false,
      error: "llm_unparseable_content",
      raw: content.slice(0, 2000),
      latencyMs: elapsed(),
    };
  }

  return {
    ok: true,
    understanding,
    raw: content,
    model,
    latencyMs: elapsed(),
  };
}
