// Deno.test unit tests for the pure helpers in receipt_understanding.ts. No
// network access — callReceiptUnderstanding is exercised through an injected
// fetch stub, and the parsing/query-building/scoring helpers run on canned
// LLM JSON responses paired with the receipt scenarios from the LLM
// enrichment plan (clear restaurant, OCR corruption, mall vendor, grocery,
// missing merchant name).
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
  buildReceiptUnderstandingMessages,
  callReceiptUnderstanding,
  chatCompletionsUrl,
  extractJsonObject,
  MAX_MERCHANT_SEARCH_QUERIES,
  MAX_OCR_PROMPT_CHARS,
  parseReceiptUnderstanding,
  resolveIncludedTypes,
  TYPE_MISMATCH_PENALTY,
  VENDOR_CATEGORY_TO_PLACE_TYPES,
} from "./receipt_understanding.ts";

// ---------------------------------------------------------------------------
// Scenario 1: clear restaurant receipt (McDonald's, Pavilion KL)
// ---------------------------------------------------------------------------

const MCD_RESPONSE = JSON.stringify({
  merchant_name: "McDonald's Pavilion KL",
  merchant_search_queries: ["McDonald's Pavilion KL", "McDonald's"],
  address_text: "168 Jalan Bukit Bintang, Kuala Lumpur",
  location_clues: ["Pavilion KL", "Bukit Bintang", "Kuala Lumpur"],
  vendor_category: "food_and_drink",
  google_place_types: ["restaurant", "fast_food_restaurant"],
  confidence: { merchant: 0.97, address: 0.9, category: 0.99 },
});

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
  assertEquals(u.confidence, { merchant: 1, address: 0, category: 0 });
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

Deno.test("prompt user message is truncated to the OCR cap", () => {
  const messages = buildReceiptUnderstandingMessages(
    "x".repeat(MAX_OCR_PROMPT_CHARS + 500),
  );
  assertEquals(messages.length, 2);
  assertEquals(messages[1].content.length, MAX_OCR_PROMPT_CHARS);
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
// callReceiptUnderstanding (injected fetch, no network)
// ---------------------------------------------------------------------------

const GATEWAY_CFG = {
  baseUrl: "http://gateway.local:31180",
  apiKey: "sk-test",
  modelName: "test-model",
  reasoningEffort: "low",
};

function chatResponse(content: string, status = 200): Response {
  return new Response(
    JSON.stringify({
      model: "test-model",
      choices: [{ message: { content } }],
    }),
    { status, headers: { "Content-Type": "application/json" } },
  );
}

Deno.test("chatCompletionsUrl normalizes bases with and without /v1", () => {
  assertEquals(
    chatCompletionsUrl("http://gw:31180"),
    "http://gw:31180/v1/chat/completions",
  );
  assertEquals(
    chatCompletionsUrl("http://gw:31180/v1/"),
    "http://gw:31180/v1/chat/completions",
  );
});

Deno.test("callReceiptUnderstanding returns a validated understanding", async () => {
  const result = await callReceiptUnderstanding(
    GATEWAY_CFG,
    "MCDONALD'S PAVILION KL...",
    () => Promise.resolve(chatResponse(MCD_RESPONSE)),
  );
  assert(result.ok);
  assertEquals(result.understanding.merchant_name, "McDonald's Pavilion KL");
  assertEquals(result.model, "test-model");
});

Deno.test("callReceiptUnderstanding retries once without response_format on 400", async () => {
  const bodies: string[] = [];
  const result = await callReceiptUnderstanding(
    GATEWAY_CFG,
    "receipt text",
    (_url, init) => {
      bodies.push(String(init?.body));
      return Promise.resolve(
        bodies.length === 1
          ? new Response("response_format unsupported", { status: 400 })
          : chatResponse(MCD_RESPONSE),
      );
    },
  );
  assert(result.ok);
  assertEquals(bodies.length, 2);
  assert(bodies[0].includes("response_format"));
  assert(!bodies[1].includes("response_format"));
});

Deno.test("callReceiptUnderstanding surfaces HTTP errors without retrying", async () => {
  let calls = 0;
  const result = await callReceiptUnderstanding(
    GATEWAY_CFG,
    "receipt text",
    () => {
      calls++;
      return Promise.resolve(new Response("boom", { status: 503 }));
    },
  );
  assert(!result.ok);
  assertEquals(result.error, "llm_http_503");
  assertEquals(calls, 1);
});

Deno.test("callReceiptUnderstanding flags unparseable content with the raw output", async () => {
  const result = await callReceiptUnderstanding(
    GATEWAY_CFG,
    "receipt text",
    () => Promise.resolve(chatResponse("I cannot read this receipt, sorry.")),
  );
  assert(!result.ok);
  assertEquals(result.error, "llm_unparseable_content");
  assertNotEquals(result.raw, null);
});

Deno.test("callReceiptUnderstanding reports fetch failures", async () => {
  const result = await callReceiptUnderstanding(
    GATEWAY_CFG,
    "receipt text",
    () => Promise.reject(new TypeError("connection refused")),
  );
  assert(!result.ok);
  assert(result.error.startsWith("llm_fetch_failed"));
});
