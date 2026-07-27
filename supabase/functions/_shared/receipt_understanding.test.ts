// Deno.test unit tests for the pure helpers in receipt_understanding.ts. No
// network access — callReceiptUnderstanding (which now calls services/ocr-api's
// POST /understand, not the LLM gateway directly — see docs/decisions.md) is
// exercised through an injected fetch stub, and the parsing/query-building/
// scoring helpers run on canned understanding JSON paired with the receipt
// scenarios from the LLM enrichment plan (clear restaurant, OCR corruption,
// mall vendor, grocery, missing merchant name). The prompt-building and LLM
// gateway-calling logic itself now lives in
// services/ocr-api/app/receipt_understanding.py — see
// services/ocr-api/tests/test_receipt_understanding.py for its tests.
//
// Run with: deno test supabase/functions/_shared/receipt_understanding.test.ts

import {
  assert,
  assertEquals,
  assertNotEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { normalizeForCompare } from "./place_matching.ts";
import {
  adjustScoreForTypeMatch,
  buildLlmTextQueries,
  callReceiptUnderstanding,
  extractJsonObject,
  MAX_MERCHANT_SEARCH_QUERIES,
  parseReceiptUnderstanding,
  resolveIncludedTypes,
  TYPE_MISMATCH_PENALTY,
  VENDOR_CATEGORY_TO_PLACE_TYPES,
} from "./receipt_understanding.ts";

// ---------------------------------------------------------------------------
// Scenario 1: clear restaurant receipt (McDonald's, Pavilion KL)
// ---------------------------------------------------------------------------

const MCD_RESPONSE_OBJ = {
  merchant_name: "McDonald's Pavilion KL",
  merchant_search_queries: ["McDonald's Pavilion KL", "McDonald's"],
  address_text: "168 Jalan Bukit Bintang, Kuala Lumpur",
  location_clues: ["Pavilion KL", "Bukit Bintang", "Kuala Lumpur"],
  vendor_category: "food_and_drink",
  google_place_types: ["restaurant", "fast_food_restaurant"],
  confidence: { merchant: 0.97, address: 0.9, category: 0.99 },
};
const MCD_RESPONSE = JSON.stringify(MCD_RESPONSE_OBJ);

Deno.test("clear restaurant: parses all fields and keeps LLM place types", () => {
  const u = parseReceiptUnderstanding(MCD_RESPONSE);
  assert(u !== null);
  assertEquals(u.merchant_name, "McDonald's Pavilion KL");
  assertEquals(u.merchant_search_queries, [
    "McDonald's Pavilion KL",
    "McDonald's",
  ]);
  assertEquals(u.vendor_category, "food_and_drink");
  assertEquals(u.google_place_types, ["restaurant", "fast_food_restaurant"]);
  assertEquals(u.confidence.merchant, 0.97);
  // LLM's own valid types win over the category defaults.
  assertEquals(resolveIncludedTypes(u), ["restaurant", "fast_food_restaurant"]);
});

Deno.test("clear restaurant: query list keeps order and skips redundant location variant", () => {
  const u = parseReceiptUnderstanding(MCD_RESPONSE)!;
  const queries = buildLlmTextQueries(u);
  // Top query already contains "Pavilion KL", so no augmented duplicate.
  assertEquals(queries, ["McDonald's Pavilion KL", "McDonald's"]);
});

// ---------------------------------------------------------------------------
// Scenario 2: OCR corruption (RESTORAN ANWAR MAU -> Restoran Anwar Maju)
// ---------------------------------------------------------------------------

const ANWAR_RESPONSE = JSON.stringify({
  merchant_name: "Restoran Anwar Maju Sdn Bhd",
  merchant_search_queries: [
    "Restoran Anwar Maju",
    "restoran anwar maju",
    "Anwar Maju",
  ],
  address_text: "Lot 12 Jalan SS2/24, Petaling Jaya",
  location_clues: ["SS2", "Petaling Jaya"],
  vendor_category: "food_and_drink",
  google_place_types: ["restaurant"],
  confidence: { merchant: 0.85, address: 0.8, category: 0.95 },
});

Deno.test("OCR corruption: corrected name yields a stable alias key", () => {
  const u = parseReceiptUnderstanding(ANWAR_RESPONSE)!;
  assertEquals(
    normalizeForCompare(u.merchant_name!),
    "restoran anwar maju sdn bhd",
  );
  // The corrected search query collapses to the same key the garbled OCR
  // variant would have needed dice-matching to reach.
  assertEquals(normalizeForCompare(u.merchant_search_queries[0]), "restoran anwar maju");
});

Deno.test("OCR corruption: queries dedupe case-insensitively", () => {
  const u = parseReceiptUnderstanding(ANWAR_RESPONSE)!;
  // "Restoran Anwar Maju" and "restoran anwar maju" collapse to one.
  assertEquals(u.merchant_search_queries, [
    "Restoran Anwar Maju",
    "Anwar Maju",
  ]);
});

// ---------------------------------------------------------------------------
// Scenario 3: mall vendor (Starbucks, 1 Utama)
// ---------------------------------------------------------------------------

const STARBUCKS_RESPONSE = JSON.stringify({
  merchant_name: "Starbucks Coffee",
  merchant_search_queries: ["Starbucks"],
  address_text: "1 Utama Shopping Centre, Petaling Jaya",
  location_clues: ["1 Utama", "Petaling Jaya"],
  vendor_category: "food_and_drink",
  google_place_types: ["cafe", "coffee_shop"],
  confidence: { merchant: 0.95, address: 0.85, category: 0.97 },
});

Deno.test("mall vendor: adds the location-augmented query variant", () => {
  const u = parseReceiptUnderstanding(STARBUCKS_RESPONSE)!;
  const queries = buildLlmTextQueries(u);
  assertEquals(queries, ["Starbucks", "Starbucks 1 Utama"]);
});

Deno.test("mall vendor: augmentation skipped when clue already in the query", () => {
  const u = parseReceiptUnderstanding(STARBUCKS_RESPONSE)!;
  const withClueBakedIn = {
    ...u,
    merchant_search_queries: ["Starbucks 1 Utama", "Starbucks"],
  };
  const queries = buildLlmTextQueries(withClueBakedIn);
  assertEquals(queries, ["Starbucks 1 Utama", "Starbucks"]);
});

// ---------------------------------------------------------------------------
// Scenario 4: grocery (Lotus's; shampoo/milk/bread line items)
// ---------------------------------------------------------------------------

Deno.test("grocery: invalid place types are filtered, valid ones kept", () => {
  const u = parseReceiptUnderstanding(JSON.stringify({
    merchant_name: "Lotus's Kepong",
    merchant_search_queries: ["Lotus's Kepong", "Lotus's"],
    address_text: null,
    location_clues: ["Kepong"],
    vendor_category: "groceries",
    // "hypermarket" is a plausible hallucination, not a Places v1 type.
    google_place_types: ["hypermarket", "supermarket"],
    confidence: { merchant: 0.9, address: 0.1, category: 0.98 },
  }))!;
  assertEquals(u.google_place_types, ["supermarket"]);
  assertEquals(resolveIncludedTypes(u), ["supermarket"]);
});

Deno.test("grocery: all-invalid types fall back to the vendor-category mapping", () => {
  const u = parseReceiptUnderstanding(JSON.stringify({
    merchant_name: "Lotus's Kepong",
    merchant_search_queries: ["Lotus's"],
    address_text: null,
    location_clues: [],
    vendor_category: "groceries",
    google_place_types: ["hypermarket", "megamart"],
    confidence: { merchant: 0.9, address: 0, category: 0.98 },
  }))!;
  assertEquals(u.google_place_types, []);
  assertEquals(
    resolveIncludedTypes(u),
    VENDOR_CATEGORY_TO_PLACE_TYPES["groceries"],
  );
});

// ---------------------------------------------------------------------------
// Scenario 5: missing merchant name, clear address (Jalan SS15 Subang Jaya)
// ---------------------------------------------------------------------------

const NO_MERCHANT_RESPONSE = JSON.stringify({
  merchant_name: null,
  merchant_search_queries: [],
  address_text: "Jalan SS15/4, Subang Jaya",
  location_clues: ["SS15", "Subang Jaya"],
  vendor_category: "food_and_drink",
  google_place_types: ["restaurant"],
  confidence: { merchant: 0.1, address: 0.85, category: 0.9 },
});

Deno.test("missing merchant: still parses (address is actionable)", () => {
  const u = parseReceiptUnderstanding(NO_MERCHANT_RESPONSE);
  assert(u !== null);
  assertEquals(u!.merchant_name, null);
  assertEquals(u!.confidence.merchant, 0.1);
});

Deno.test("missing merchant: produces a category-hint + address query", () => {
  const u = parseReceiptUnderstanding(NO_MERCHANT_RESPONSE)!;
  assertEquals(buildLlmTextQueries(u), ["restaurant Jalan SS15/4, Subang Jaya"]);
});

Deno.test("missing merchant with no address at all parses to null", () => {
  const u = parseReceiptUnderstanding(JSON.stringify({
    merchant_name: null,
    merchant_search_queries: [],
    address_text: null,
    location_clues: [],
    vendor_category: "other",
    google_place_types: [],
    confidence: { merchant: 0, address: 0, category: 0.2 },
  }));
  assertEquals(u, null);
});

// ---------------------------------------------------------------------------
// Robustness: chatty/malformed model output
// ---------------------------------------------------------------------------

Deno.test("extractJsonObject strips markdown fences", () => {
  const raw = "```json\n" + MCD_RESPONSE + "\n```";
  assertEquals(extractJsonObject(raw), MCD_RESPONSE);
  assert(parseReceiptUnderstanding(raw) !== null);
});

Deno.test("extractJsonObject strips <think> blocks", () => {
  const raw = "<think>The receipt mentions Pavilion KL so this is likely" +
    " the Bukit Bintang outlet.</think>" + MCD_RESPONSE;
  assert(parseReceiptUnderstanding(raw) !== null);
});

Deno.test("parseReceiptUnderstanding survives leading and trailing prose", () => {
  const raw = "Sure! Here is the JSON you asked for:\n" + MCD_RESPONSE +
    "\nLet me know if you need anything else.";
  const u = parseReceiptUnderstanding(raw);
  assert(u !== null);
  assertEquals(u!.merchant_name, "McDonald's Pavilion KL");
});

Deno.test("out-of-range confidences are clamped", () => {
  const u = parseReceiptUnderstanding(JSON.stringify({
    merchant_name: "Kedai Ali",
    merchant_search_queries: ["Kedai Ali"],
    address_text: null,
    location_clues: [],
    vendor_category: "groceries",
    google_place_types: [],
    confidence: { merchant: 1.7, address: -0.4, category: "high" },
  }))!;
  assertEquals(u.confidence, {
    merchant: 1,
    address: 0,
    category: 0,
    line_items: 0,
  });
});

Deno.test("non-array merchant_search_queries coerces to empty", () => {
  const u = parseReceiptUnderstanding(JSON.stringify({
    merchant_name: "Kedai Ali",
    merchant_search_queries: "Kedai Ali",
    address_text: null,
    location_clues: [],
    vendor_category: null,
    google_place_types: [],
    confidence: {},
  }))!;
  assertEquals(u.merchant_search_queries, []);
  // buildLlmTextQueries recovers by falling back to merchant_name.
  assertEquals(buildLlmTextQueries(u), ["Kedai Ali"]);
});

Deno.test("off-vocabulary vendor_category is nulled", () => {
  const u = parseReceiptUnderstanding(JSON.stringify({
    merchant_name: "Kedai Ali",
    merchant_search_queries: ["Kedai Ali"],
    address_text: null,
    location_clues: [],
    vendor_category: "restaurant_and_bar",
    google_place_types: [],
    confidence: {},
  }))!;
  assertEquals(u.vendor_category, null);
});

Deno.test("totally unparseable output returns null", () => {
  assertEquals(parseReceiptUnderstanding("I could not read this receipt."), null);
  assertEquals(parseReceiptUnderstanding(""), null);
  assertEquals(parseReceiptUnderstanding("{not json"), null);
});

Deno.test("more than 3 queries are capped", () => {
  const u = parseReceiptUnderstanding(JSON.stringify({
    merchant_name: "Restoran Lima Nama",
    merchant_search_queries: ["One", "Two", "Three", "Four", "Five"],
    address_text: null,
    location_clues: [],
    vendor_category: "food_and_drink",
    google_place_types: [],
    confidence: {},
  }))!;
  assertEquals(u.merchant_search_queries.length, MAX_MERCHANT_SEARCH_QUERIES);
  assert(buildLlmTextQueries(u).length <= MAX_MERCHANT_SEARCH_QUERIES);
});

// ---------------------------------------------------------------------------
// line_items
// ---------------------------------------------------------------------------

Deno.test("line_items parsed and coerced", () => {
  const u = parseReceiptUnderstanding(JSON.stringify({
    merchant_name: "Sample Store",
    merchant_search_queries: ["Sample Store"],
    address_text: null,
    location_clues: [],
    vendor_category: "groceries",
    google_place_types: [],
    line_items: [
      { name: "Milk", price: 4.5, quantity: 1 },
      { name: "Bread", price: "3.20", quantity: null },
      { name: "Eggs", price: null, quantity: 2 },
    ],
    confidence: { merchant: 0.9, address: 0.1, category: 0.9, line_items: 0.8 },
  }))!;
  assertEquals(u.line_items.length, 3);
  assertEquals(u.line_items[0], { name: "Milk", price: 4.5, quantity: 1 });
  assertEquals(u.line_items[1].price, 3.2);
  assertEquals(u.line_items[2].price, null);
  assertEquals(u.line_items[2].quantity, 2);
  assertEquals(u.confidence.line_items, 0.8);
});

Deno.test("line_items malformed entries dropped", () => {
  const u = parseReceiptUnderstanding(JSON.stringify({
    merchant_name: "Sample Store",
    merchant_search_queries: [],
    address_text: null,
    location_clues: [],
    vendor_category: "groceries",
    google_place_types: [],
    line_items: [
      { name: "Milk", price: 4.5 },
      { name: null, price: 9.9 }, // no name -> dropped
      "not an object", // dropped
      { name: "Bad Price", price: "free" }, // unparseable price kept as null
      { name: "Negative", price: -5 }, // negative price coerced to null
    ],
    confidence: {},
  }))!;
  assertEquals(u.line_items.map((it) => it.name), [
    "Milk",
    "Bad Price",
    "Negative",
  ]);
  assertEquals(u.line_items[1].price, null);
  assertEquals(u.line_items[2].price, null);
});

Deno.test("line_items capped at MAX_LINE_ITEMS", () => {
  const u = parseReceiptUnderstanding(JSON.stringify({
    merchant_name: "Big Receipt",
    merchant_search_queries: [],
    address_text: null,
    location_clues: [],
    vendor_category: "groceries",
    google_place_types: [],
    line_items: Array.from({ length: 60 }, (_, i) => ({
      name: `Item ${i}`,
      price: 1,
    })),
    confidence: {},
  }))!;
  assertEquals(u.line_items.length, MAX_LINE_ITEMS);
});

Deno.test("actionable via line_items only", () => {
  const u = parseReceiptUnderstanding(JSON.stringify({
    merchant_name: null,
    merchant_search_queries: [],
    address_text: null,
    location_clues: [],
    vendor_category: null,
    google_place_types: [],
    line_items: [{ name: "Mystery Item", price: 5 }],
    confidence: {},
  }));
  assert(u !== null);
  assertEquals(u!.line_items.length, 1);
});

// ---------------------------------------------------------------------------
// OCR cleanup fields (cleaned_lines/cleaned_ocr_text/corrections) — mirrors
// ocr-api's ReceiptUnderstandingResponse additions. In practice
// parseReceiptUnderstanding never sees these today (POST /understand, the
// only caller in this codebase, never sends per-line data — see
// receipt_understanding.ts's ReceiptUnderstanding doc comment), but this
// mirror must not silently drop them if that ever changes.
// ---------------------------------------------------------------------------

Deno.test("cleanup fields are parsed through when present", () => {
  const u = parseReceiptUnderstanding(JSON.stringify({
    ...MCD_RESPONSE_OBJ,
    cleaned_lines: ["MCDONALD'S PAVILION KL", "TOTAL RM7.70"],
    cleaned_ocr_text: "MCDONALD'S PAVILION KL\nTOTAL RM7.70",
    corrections: [
      { line_index: 1, original: "T0TAL RM7.70", corrected: "TOTAL RM7.70" },
    ],
  }));
  assert(u !== null);
  assertEquals(u!.cleaned_lines, ["MCDONALD'S PAVILION KL", "TOTAL RM7.70"]);
  assertEquals(u!.cleaned_ocr_text, "MCDONALD'S PAVILION KL\nTOTAL RM7.70");
  assertEquals(u!.corrections, [
    { line_index: 1, original: "T0TAL RM7.70", corrected: "TOTAL RM7.70" },
  ]);
});

Deno.test("cleanup fields are absent (not null/empty-array) when the LLM response omits them", () => {
  const u = parseReceiptUnderstanding(MCD_RESPONSE);
  assert(u !== null);
  assertEquals(u!.cleaned_lines, undefined);
  assertEquals(u!.cleaned_ocr_text, undefined);
  assertEquals(u!.corrections, undefined);
});

Deno.test("malformed corrections entries are dropped, not fatal", () => {
  const u = parseReceiptUnderstanding(JSON.stringify({
    ...MCD_RESPONSE_OBJ,
    corrections: [
      { line_index: 0, original: "A", corrected: "B" },
      { line_index: "not a number", original: "C", corrected: "D" },
      { original: "missing line_index", corrected: "X" },
      "not an object",
      null,
    ],
  }));
  assert(u !== null);
  assertEquals(u!.corrections, [{ line_index: 0, original: "A", corrected: "B" }]);
});

Deno.test("cleaned_ocr_text falls back to joined cleaned_lines when absent", () => {
  const u = parseReceiptUnderstanding(JSON.stringify({
    ...MCD_RESPONSE_OBJ,
    cleaned_lines: ["Line one", "Line two"],
  }));
  assert(u !== null);
  assertEquals(u!.cleaned_ocr_text, "Line one\nLine two");
});

// ---------------------------------------------------------------------------
// adjustScoreForTypeMatch
// ---------------------------------------------------------------------------

Deno.test("type mismatch penalizes the score", () => {
  const adjusted = adjustScoreForTypeMatch(
    0.8,
    ["clothing_store", "shoe_store"],
    ["restaurant", "cafe"],
  );
  assertEquals(adjusted, 0.8 * TYPE_MISMATCH_PENALTY);
  assert(adjusted < 0.5);
});

Deno.test("type overlap leaves the score unchanged", () => {
  assertEquals(
    adjustScoreForTypeMatch(0.8, ["restaurant", "bar"], ["restaurant"]),
    0.8,
  );
});

Deno.test("missing candidate or expected types are neutral", () => {
  assertEquals(adjustScoreForTypeMatch(0.8, null, ["restaurant"]), 0.8);
  assertEquals(adjustScoreForTypeMatch(0.8, [], ["restaurant"]), 0.8);
  assertEquals(adjustScoreForTypeMatch(0.8, ["clothing_store"], []), 0.8);
});

// ---------------------------------------------------------------------------
// callReceiptUnderstanding (injected fetch, no network — calls services/
// ocr-api's POST /understand, which is what actually talks to the LLM
// gateway now; see services/ocr-api/tests/test_receipt_understanding.py)
// ---------------------------------------------------------------------------

const OCR_API_CFG = {
  ocrServiceUrl: "http://ocr-api.local:8081",
  ocrServiceSecret: "shared-secret",
};

function understandResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.test("callReceiptUnderstanding posts to {ocrServiceUrl}/understand with the shared secret", async () => {
  let seenUrl: string | undefined;
  let seenSecret: string | null | undefined;
  const result = await callReceiptUnderstanding(
    OCR_API_CFG,
    "MCDONALD'S PAVILION KL...",
    (url, init) => {
      seenUrl = String(url);
      seenSecret = (init?.headers as Record<string, string>)["X-OCR-Secret"];
      return Promise.resolve(understandResponse(MCD_RESPONSE_OBJ));
    },
  );
  assertEquals(seenUrl, "http://ocr-api.local:8081/understand");
  assertEquals(seenSecret, "shared-secret");
  assert(result.ok);
  assertEquals(result.understanding.merchant_name, "McDonald's Pavilion KL");
});

Deno.test("callReceiptUnderstanding surfaces HTTP errors without retrying", async () => {
  let calls = 0;
  const result = await callReceiptUnderstanding(
    OCR_API_CFG,
    "receipt text",
    () => {
      calls++;
      return Promise.resolve(
        understandResponse({ error: "llm_http_503" }, 502),
      );
    },
  );
  assert(!result.ok);
  assertEquals(result.error, "llm_http_502");
  assertEquals(calls, 1);
});

Deno.test("callReceiptUnderstanding flags unparseable content with the raw output", async () => {
  // Defense-in-depth: even though ocr-api validates before responding, a
  // malformed/empty 200 must still fail closed here, not crash or coerce.
  const result = await callReceiptUnderstanding(
    OCR_API_CFG,
    "receipt text",
    () =>
      Promise.resolve(understandResponse({
        merchant_name: null,
        merchant_search_queries: [],
        address_text: null,
        location_clues: [],
        vendor_category: null,
        google_place_types: [],
        confidence: { merchant: 0, address: 0, category: 0 },
      })),
  );
  assert(!result.ok);
  assertEquals(result.error, "llm_unparseable_content");
  assertNotEquals(result.raw, null);
});

Deno.test("callReceiptUnderstanding reports fetch failures", async () => {
  const result = await callReceiptUnderstanding(
    OCR_API_CFG,
    "receipt text",
    () => Promise.reject(new TypeError("connection refused")),
  );
  assert(!result.ok);
  assert(result.error.startsWith("llm_fetch_failed"));
});
