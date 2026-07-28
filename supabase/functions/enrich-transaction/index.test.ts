// Deno integration tests for enrich-transaction's `handleEnrichTransactionRequest`
// (extracted from the file's former top-level `Deno.serve(...)` — see the
// `import.meta.main` guard at the bottom of index.ts). Unlike
// merchant_resolution.test.ts/place_matching.test.ts, this file deliberately
// exercises the REAL local Supabase Postgres + Auth (no mocking of the
// database or JWT verification) with only Google Places' `fetch` calls
// mocked — mirroring the fetchFn-injection precedent already used by
// `callReceiptUnderstanding` (receipt_understanding.ts).
//
// Requires a running local Supabase stack (`supabase status` to confirm; the
// well-known local CLI default URL/keys are hardcoded below — override via
// TEST_SUPABASE_* env vars if your local stack uses non-default ports/keys).
//
// Run with:
//   deno test --allow-net --allow-env supabase/functions/enrich-transaction/index.test.ts
// (--allow-net: real HTTP calls to the local Supabase REST/Auth API and
// Postgres-over-HTTP; --allow-env: reads/writes MERCHANT_INTELLIGENCE_MODE,
// SUPABASE_URL, SUPABASE_ANON_KEY, GOOGLE_PLACES_API_KEY via Deno.env.)
//
// Every test creates its own uniquely-named (crypto.randomUUID()-suffixed)
// transactions/merchants/merchant_locations/merchant_aliases fixture rows via
// a service-role client (bypassing RLS) and deletes them in a `finally`
// block, so repeated runs of this file never accumulate cruft in the shared
// local dev database. The one test user created in `setup` is deleted in the
// final `cleanup` test, which also cascade-deletes (via
// profiles/transactions' `on delete cascade` FKs) any transaction row a
// scenario's own cleanup might have missed — a defense-in-depth backstop,
// not a substitute for each scenario's own explicit cleanup.

import {
  assert,
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { ALIAS_MIN_TRUST_CONFIDENCE } from "../_shared/place_matching.ts";
import { handleEnrichTransactionRequest } from "./index.ts";

// ---------------------------------------------------------------------------
// Local dev stack connection info — the standard `supabase init` CLI
// defaults for this repo (confirmed against supabase/config.toml's
// [api] port = 54321, and `supabase status`'s well-known demo JWTs, which
// are public fixture values baked into every local Supabase CLI project, not
// a secret). Overridable for a non-default local setup.
// ---------------------------------------------------------------------------
const SUPABASE_URL = Deno.env.get("TEST_SUPABASE_URL") ?? "http://127.0.0.1:54321";
const ANON_KEY = Deno.env.get("TEST_SUPABASE_ANON_KEY") ??
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0";
const SERVICE_ROLE_KEY = Deno.env.get("TEST_SUPABASE_SERVICE_ROLE_KEY") ??
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU";

// The handler under test reads these itself via `Deno.env.get(...)` — a bare
// `deno test` process has neither, unlike `supabase functions serve`'s
// injected environment, so this file must set them up front.
Deno.env.set("SUPABASE_URL", SUPABASE_URL);
Deno.env.set("SUPABASE_ANON_KEY", ANON_KEY);
// Never actually sent over the wire (fetchFn is always mocked below) — only
// needs to be non-empty so the handler's `if (!apiKey)` guard doesn't
// short-circuit before Places is ever "called".
Deno.env.set("GOOGLE_PLACES_API_KEY", "test-fake-google-places-key");

const admin: SupabaseClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

// Every Deno.test below makes real network calls (Postgres/Auth over HTTP
// via supabase-js) — sanitizers otherwise flag normal keep-alive connection
// reuse across tests as a "leak".
const NET_TEST_OPTS = { sanitizeOps: false, sanitizeResources: false } as const;

let testUserId = "";
let testAccessToken = "";

// ---------------------------------------------------------------------------
// Fixture helpers
// ---------------------------------------------------------------------------

/** A minimal-but-valid `ReceiptUnderstanding`-shaped object (see
 * supabase/functions/_shared/receipt_understanding.ts) — just enough for
 * `parseReceiptUnderstanding` to accept it and for `hasUsableText` to be
 * true (confidence.merchant >= 0.6, isUsableMerchantText(merchantName)). */
function buildUnderstanding(opts: {
  merchantName: string;
  searchQueries?: string[];
  addressText?: string | null;
  locationClues?: string[];
  vendorCategory?: string;
  placeTypes?: string[];
  merchantConfidence?: number;
  receiptType?: string;
}): Record<string, unknown> {
  return {
    merchant_name: opts.merchantName,
    merchant_search_queries: opts.searchQueries ?? [opts.merchantName],
    address_text: opts.addressText ?? null,
    location_clues: opts.locationClues ?? [],
    vendor_category: opts.vendorCategory ?? "food_and_drink",
    google_place_types: opts.placeTypes ?? ["cafe"],
    line_items: [],
    confidence: {
      merchant: opts.merchantConfidence ?? 0.95,
      address: 0.4,
      category: 0.9,
      line_items: 0,
    },
    ...(opts.receiptType ? { receipt_type: opts.receiptType } : {}),
  };
}

interface TransactionFixture {
  id: string;
  share_location_lat?: number | null;
  share_location_lng?: number | null;
  merchant_raw?: string | null;
  llm_understanding?: Record<string, unknown> | null;
  place_status?: "guess" | "user_locked" | "none";
  place_google_place_id?: string | null;
  place_name?: string | null;
  place_lat?: number | null;
  place_lng?: number | null;
  place_confidence?: number | null;
}

async function insertTransaction(fx: TransactionFixture): Promise<void> {
  const { error } = await admin.from("transactions").insert({
    user_id: testUserId,
    ...fx,
  });
  if (error) throw new Error(`insertTransaction failed: ${error.message}`);
}

async function fetchTransaction(id: string) {
  const { data, error } = await admin
    .from("transactions")
    .select("*")
    .eq("id", id)
    .single();
  if (error) throw new Error(`fetchTransaction failed: ${error.message}`);
  return data;
}

async function deleteTransaction(id: string): Promise<void> {
  await admin.from("transactions").delete().eq("id", id);
}

async function deleteMerchantByCanonicalName(name: string): Promise<void> {
  // `merchant_locations.merchant_id` is `on delete cascade`, so this also
  // removes any location(s) created under this merchant.
  await admin.from("merchants").delete().eq("canonical_name", name);
}

async function deleteMerchantLocationByPlaceId(placeId: string): Promise<void> {
  await admin.from("merchant_locations").delete().eq("google_place_id", placeId);
}

async function deleteMerchantAliasByPlaceId(placeId: string): Promise<void> {
  await admin.from("merchant_aliases").delete().eq("canonical_place_id", placeId);
}

async function findMerchantByCanonicalName(name: string) {
  const { data } = await admin
    .from("merchants")
    .select("*")
    .eq("canonical_name", name)
    .maybeSingle();
  return data;
}

function setMode(mode: "off" | "shadow" | "on" | undefined): void {
  if (mode) {
    Deno.env.set("MERCHANT_INTELLIGENCE_MODE", mode);
  } else {
    Deno.env.delete("MERCHANT_INTELLIGENCE_MODE");
  }
}

function buildRequest(transactionId: string): Request {
  return new Request("http://localhost/", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${testAccessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ transaction_id: transactionId }),
  });
}

interface MockPlace {
  id: string;
  name: string;
  lat: number;
  lng: number;
  types?: string[];
}

/** Stubs `fetchTextSearch`/`fetchNearbySearch`'s network calls. Fails loudly
 * (throws) on any URL that isn't a Google Places endpoint, so an accidental
 * real network call from elsewhere in the handler is never silently
 * swallowed. `onPlacesCall` lets a test assert Places was (or wasn't)
 * actually invoked, independent of the response contents. */
function makeMockFetch(
  places: MockPlace[],
  opts?: {
    fail?: boolean;
    onPlacesCall?: () => void;
    onRequest?: (url: string, body: Record<string, unknown>) => void;
  },
): typeof fetch {
  return (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = typeof input === "string"
      ? input
      : input instanceof URL
      ? input.toString()
      : input.url;
    if (!url.includes("places.googleapis.com")) {
      throw new Error(
        `mockFetch: unexpected non-Places call to ${url} — this test's ` +
          `fetchFn only supports places.googleapis.com`,
      );
    }
    if (init?.body && typeof init.body === "string") {
      opts?.onRequest?.(url, JSON.parse(init.body) as Record<string, unknown>);
    }
    opts?.onPlacesCall?.();
    if (opts?.fail) {
      return new Response("mocked places failure", { status: 500 });
    }
    return new Response(
      JSON.stringify({
        places: places.map((p) => ({
          id: p.id,
          displayName: { text: p.name },
          location: { latitude: p.lat, longitude: p.lng },
          types: p.types ?? [],
        })),
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  }) as typeof fetch;
}

// ---------------------------------------------------------------------------
// Setup / teardown (Deno.test has no beforeAll/afterAll — tests in one file
// run sequentially in declaration order by default, so a first "setup" test
// and a final "cleanup" test bracket the rest, per this repo's own guidance
// for this scenario).
// ---------------------------------------------------------------------------

Deno.test("setup: create a real local-Auth test user and sign in", NET_TEST_OPTS, async () => {
  const email = `enrich-mi-test-${crypto.randomUUID()}@example.com`;
  const password = "TestPassword123!";

  const { data: created, error: createErr } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });
  if (createErr || !created.user) {
    throw new Error(`test user creation failed: ${createErr?.message}`);
  }
  testUserId = created.user.id;

  const anon = createClient(SUPABASE_URL, ANON_KEY);
  const { data: signIn, error: signInErr } = await anon.auth.signInWithPassword({
    email,
    password,
  });
  if (signInErr || !signIn.session) {
    throw new Error(`test user sign-in failed: ${signInErr?.message}`);
  }
  testAccessToken = signIn.session.access_token;

  assertExists(testUserId);
  assertExists(testAccessToken);
});

// ---------------------------------------------------------------------------
// 1. MERCHANT_INTELLIGENCE_MODE=off — unchanged pre-existing behavior.
// ---------------------------------------------------------------------------
Deno.test("mode=off: resolves via Places as before, merchant/location columns stay null, no merchants row created", NET_TEST_OPTS, async () => {
  const runId = crypto.randomUUID().slice(0, 8);
  const txId = crypto.randomUUID();
  const merchantName = `Kopi Off Mode ${runId}`;
  const placeId = `place-off-${runId}`;

  setMode("off");
  try {
    await insertTransaction({
      id: txId,
      share_location_lat: 3.15,
      share_location_lng: 101.7,
      llm_understanding: buildUnderstanding({ merchantName }),
    });

    const mockFetch = makeMockFetch([
      { id: placeId, name: merchantName, lat: 3.15, lng: 101.7, types: ["cafe"] },
    ]);
    const resp = await handleEnrichTransactionRequest(buildRequest(txId), {
      fetchFn: mockFetch,
    });
    const body = await resp.json();
    assertEquals(resp.status, 200);
    assertEquals(body.ok, true);

    const row = await fetchTransaction(txId);
    assertEquals(row.pipeline_status, "enriched");
    assertEquals(row.place_google_place_id, placeId);
    assertEquals(row.merchant_id, null);
    assertEquals(row.merchant_location_id, null);
    assertEquals(row.merchant_resolution_method, null);

    const merchant = await findMerchantByCanonicalName(merchantName);
    assertEquals(merchant, null, "off mode must never create a merchants row");
  } finally {
    await deleteTransaction(txId);
    await deleteMerchantAliasByPlaceId(placeId);
    setMode(undefined);
  }
});

// ---------------------------------------------------------------------------
// 2. MERCHANT_INTELLIGENCE_MODE=shadow — decision computed/logged, never
//    persisted.
// ---------------------------------------------------------------------------
Deno.test("mode=shadow: logs a decision but writes nothing to merchant_id/merchants/merchant_locations", NET_TEST_OPTS, async () => {
  const runId = crypto.randomUUID().slice(0, 8);
  const txId = crypto.randomUUID();
  const merchantName = `Kopi Shadow Mode ${runId}`;
  const placeId = `place-shadow-${runId}`;

  setMode("shadow");
  const originalLog = console.log;
  const logs: string[] = [];
  console.log = (...args: unknown[]) => {
    logs.push(args.map(String).join(" "));
  };
  try {
    await insertTransaction({
      id: txId,
      share_location_lat: 3.15,
      share_location_lng: 101.7,
      llm_understanding: buildUnderstanding({ merchantName }),
    });

    const mockFetch = makeMockFetch([
      { id: placeId, name: merchantName, lat: 3.15, lng: 101.7, types: ["cafe"] },
    ]);
    const resp = await handleEnrichTransactionRequest(buildRequest(txId), {
      fetchFn: mockFetch,
    });
    assertEquals(resp.status, 200);

    assert(
      logs.some((l) => l.includes("merchant-intelligence") && l.includes("shadow")),
      "expected a shadow-mode merchant-intelligence decision log line",
    );

    const row = await fetchTransaction(txId);
    assertEquals(row.merchant_id, null);
    assertEquals(row.merchant_location_id, null);

    const merchant = await findMerchantByCanonicalName(merchantName);
    assertEquals(merchant, null, "shadow mode must never create a merchants row");
  } finally {
    console.log = originalLog;
    await deleteTransaction(txId);
    await deleteMerchantAliasByPlaceId(placeId);
    setMode(undefined);
  }
});

// ---------------------------------------------------------------------------
// 3. MERCHANT_INTELLIGENCE_MODE=on — brand-new merchant + location.
// ---------------------------------------------------------------------------
Deno.test("mode=on: brand-new merchant/location created and attached, counters start at 1", NET_TEST_OPTS, async () => {
  const runId = crypto.randomUUID().slice(0, 8);
  const txId = crypto.randomUUID();
  const merchantName = `Kopi On Mode New ${runId}`;
  const placeId = `place-on-new-${runId}`;

  setMode("on");
  try {
    await insertTransaction({
      id: txId,
      share_location_lat: 3.15,
      share_location_lng: 101.7,
      llm_understanding: buildUnderstanding({ merchantName }),
    });

    const mockFetch = makeMockFetch([
      { id: placeId, name: merchantName, lat: 3.15, lng: 101.7, types: ["cafe"] },
    ]);
    const resp = await handleEnrichTransactionRequest(buildRequest(txId), {
      fetchFn: mockFetch,
    });
    assertEquals(resp.status, 200);

    const row = await fetchTransaction(txId);
    assertExists(row.merchant_id);
    assertExists(row.merchant_location_id);
    assertEquals(row.merchant_resolution_method, "places_search");

    const { data: merchant } = await admin
      .from("merchants")
      .select("*")
      .eq("id", row.merchant_id)
      .single();
    assertEquals(merchant.canonical_name, merchantName);
    assertEquals(merchant.observation_count, 1);

    const { data: location } = await admin
      .from("merchant_locations")
      .select("*")
      .eq("id", row.merchant_location_id)
      .single();
    assertEquals(location.google_place_id, placeId);
    assertEquals(location.hit_count, 1);
  } finally {
    await deleteTransaction(txId);
    await deleteMerchantByCanonicalName(merchantName);
    await deleteMerchantAliasByPlaceId(placeId);
    setMode(undefined);
  }
});

// ---------------------------------------------------------------------------
// 4. MERCHANT_INTELLIGENCE_MODE=on — attach to an existing known merchant.
// ---------------------------------------------------------------------------
Deno.test("mode=on: attaches to a pre-seeded existing merchant instead of creating a new one", NET_TEST_OPTS, async () => {
  const runId = crypto.randomUUID().slice(0, 8);
  const txId = crypto.randomUUID();
  // Identical text on both the brand-candidate side and the Places-winner
  // side trivially clears BRAND_AGREEMENT_THRESHOLD/PLACES_AGREEMENT_THRESHOLD
  // (dice coefficient of a string against itself is 1.0) without needing to
  // construct a fuzzy near-match — the agreement logic itself is already
  // covered by merchant_resolution.test.ts.
  const merchantName = `Restoran Existing Brand ${runId}`;
  const placeId = `place-on-existing-${runId}`;

  const { data: seeded, error: seedErr } = await admin
    .from("merchants")
    .insert({
      canonical_name: merchantName,
      normalized_name_key: merchantName.toLowerCase(),
    })
    .select("*")
    .single();
  if (seedErr || !seeded) {
    throw new Error(`failed to seed existing merchant: ${seedErr?.message}`);
  }

  setMode("on");
  try {
    await insertTransaction({
      id: txId,
      share_location_lat: 3.15,
      share_location_lng: 101.7,
      llm_understanding: buildUnderstanding({ merchantName }),
    });

    const mockFetch = makeMockFetch([
      { id: placeId, name: merchantName, lat: 3.15, lng: 101.7, types: ["cafe"] },
    ]);
    const resp = await handleEnrichTransactionRequest(buildRequest(txId), {
      fetchFn: mockFetch,
    });
    assertEquals(resp.status, 200);

    const row = await fetchTransaction(txId);
    assertEquals(row.merchant_id, seeded.id, "should attach to the pre-seeded merchant");
    assertEquals(row.merchant_resolution_method, "fuzzy_brand");

    const { data: merchantAfter } = await admin
      .from("merchants")
      .select("*")
      .eq("id", seeded.id)
      .single();
    assertEquals(
      merchantAfter.observation_count,
      2,
      "attaching a transaction to an already-existing merchant increments observation_count",
    );

    const { count } = await admin
      .from("merchants")
      .select("*", { count: "exact", head: true })
      .eq("canonical_name", merchantName);
    assertEquals(count, 1, "no second merchants row should have been created");
  } finally {
    await deleteTransaction(txId);
    await deleteMerchantByCanonicalName(merchantName);
    await deleteMerchantAliasByPlaceId(placeId);
    setMode(undefined);
  }
});

// ---------------------------------------------------------------------------
// 5. MERCHANT_INTELLIGENCE_MODE=on — idempotent retry through the real Edge
//    code path (not just directly against the SQL RPC, which Task 3's pgTAP
//    suite already covers).
// ---------------------------------------------------------------------------
Deno.test("mode=on: retrying the same transaction does not double-increment merchant/location counters", NET_TEST_OPTS, async () => {
  const runId = crypto.randomUUID().slice(0, 8);
  const txId = crypto.randomUUID();
  const merchantName = `Kopi Idempotent Retry ${runId}`;
  const placeId = `place-idempotent-${runId}`;

  setMode("on");
  try {
    await insertTransaction({
      id: txId,
      // ~144m offset from the mocked Places winner's coordinates below —
      // keeps this scenario's Places-match confidence below
      // ALIAS_SAVE_CONFIDENCE_THRESHOLD (0.85, place_matching.ts) so the
      // second call falls through to the full Places+MI path again instead
      // of short-circuiting via the alias fast-path (which never reaches
      // the merchant-intelligence block at all) — the whole point of this
      // test is to exercise reconcile_merchant_resolution's idempotency
      // through the Edge path twice, not to hit the alias cache.
      share_location_lat: 3.15,
      share_location_lng: 101.7,
      llm_understanding: buildUnderstanding({ merchantName }),
    });

    const mockFetch = makeMockFetch([
      { id: placeId, name: merchantName, lat: 3.1513, lng: 101.7, types: ["cafe"] },
    ]);

    const first = await handleEnrichTransactionRequest(buildRequest(txId), {
      fetchFn: mockFetch,
    });
    assertEquals(first.status, 200);

    const rowAfterFirst = await fetchTransaction(txId);
    assertExists(rowAfterFirst.merchant_id);
    assertExists(rowAfterFirst.merchant_location_id);
    assert(
      (rowAfterFirst.place_confidence as number) < 0.85,
      `test fixture assumption violated: place_confidence should be < 0.85 to avoid the alias fast-path, got ${rowAfterFirst.place_confidence}`,
    );

    const second = await handleEnrichTransactionRequest(buildRequest(txId), {
      fetchFn: mockFetch,
    });
    assertEquals(second.status, 200);

    const { data: merchantAfter } = await admin
      .from("merchants")
      .select("*")
      .eq("id", rowAfterFirst.merchant_id)
      .single();
    assertEquals(
      merchantAfter.observation_count,
      1,
      "a freshly-created merchant retried on the same transaction must stay at observation_count = 1",
    );

    const { data: locationAfter } = await admin
      .from("merchant_locations")
      .select("*")
      .eq("id", rowAfterFirst.merchant_location_id)
      .single();
    assertEquals(
      locationAfter.hit_count,
      1,
      "a freshly-created location retried on the same transaction must stay at hit_count = 1",
    );
  } finally {
    const row = await fetchTransaction(txId).catch(() => null);
    await deleteTransaction(txId);
    if (row?.merchant_id) {
      const { data: m } = await admin
        .from("merchants")
        .select("canonical_name")
        .eq("id", row.merchant_id)
        .maybeSingle();
      if (m) await deleteMerchantByCanonicalName(m.canonical_name);
    }
    await deleteMerchantAliasByPlaceId(placeId);
    setMode(undefined);
  }
});

// ---------------------------------------------------------------------------
// 6. Places call failure — unchanged existing failure behavior; MI must
//    never be reached (there's no winner to reconcile).
// ---------------------------------------------------------------------------
Deno.test("Places failure: falls back to today's failed_enrichment/places_error behavior, MI never reached", NET_TEST_OPTS, async () => {
  const runId = crypto.randomUUID().slice(0, 8);
  const txId = crypto.randomUUID();
  const merchantName = `Kopi Places Down ${runId}`;

  setMode("on"); // even "on" must not matter — there is no Places winner.
  try {
    await insertTransaction({
      id: txId,
      share_location_lat: 3.15,
      share_location_lng: 101.7,
      llm_understanding: buildUnderstanding({ merchantName }),
    });

    const mockFetch = makeMockFetch([], { fail: true });
    const resp = await handleEnrichTransactionRequest(buildRequest(txId), {
      fetchFn: mockFetch,
    });
    const body = await resp.json();
    assertEquals(resp.status, 200);
    assertEquals(body.ok, false);
    assertEquals(body.reason, "places_error");

    const row = await fetchTransaction(txId);
    assertEquals(row.pipeline_status, "failed_enrichment");
    assertEquals(row.merchant_id, null);
    assertEquals(row.merchant_location_id, null);

    const merchant = await findMerchantByCanonicalName(merchantName);
    assertEquals(merchant, null);
  } finally {
    await deleteTransaction(txId);
    setMode(undefined);
  }
});

// ---------------------------------------------------------------------------
// 7. user_locked early-return branch — reconciles without ever calling
//    Places.
// ---------------------------------------------------------------------------
Deno.test("user_locked: reconciles via the early-return branch and never calls Places", NET_TEST_OPTS, async () => {
  const runId = crypto.randomUUID().slice(0, 8);
  const txId = crypto.randomUUID();
  const merchantName = `Restoran User Locked ${runId}`;
  const placeId = `place-user-locked-${runId}`;

  setMode("on");
  let placesCallCount = 0;
  try {
    await insertTransaction({
      id: txId,
      share_location_lat: 3.15,
      share_location_lng: 101.7,
      llm_understanding: buildUnderstanding({ merchantName }),
      place_status: "user_locked",
      place_google_place_id: placeId,
      place_name: merchantName,
      place_lat: 3.15,
      place_lng: 101.7,
    });

    const mockFetch = makeMockFetch(
      [{ id: placeId, name: merchantName, lat: 3.15, lng: 101.7 }],
      { onPlacesCall: () => placesCallCount++ },
    );
    const resp = await handleEnrichTransactionRequest(buildRequest(txId), {
      fetchFn: mockFetch,
    });
    assertEquals(resp.status, 200);

    assertEquals(placesCallCount, 0, "user_locked must never call the live Places endpoints");

    const row = await fetchTransaction(txId);
    assertEquals(row.pipeline_status, "enriched");
    assertEquals(row.merchant_resolution_method, "user_locked");
    assertExists(row.merchant_id);
    assertExists(row.merchant_location_id);
  } finally {
    await deleteTransaction(txId);
    await deleteMerchantByCanonicalName(merchantName);
    await deleteMerchantLocationByPlaceId(placeId);
    await deleteMerchantAliasByPlaceId(placeId);
    setMode(undefined);
  }
});

// ---------------------------------------------------------------------------
// 8. ALIAS_MIN_TRUST_CONFIDENCE gate.
// ---------------------------------------------------------------------------
Deno.test("alias gate: a below-floor alias hit falls through to Places instead of being trusted", NET_TEST_OPTS, async () => {
  const runId = crypto.randomUUID().slice(0, 8);
  const txId = crypto.randomUUID();
  const merchantName = `Kedai Decayed Alias ${runId}`;
  const decayedAliasPlaceId = `place-decayed-alias-${runId}`;
  const freshPlaceId = `place-fresh-fallback-${runId}`;
  const lat = 3.15;
  const lng = 101.7;
  // Same geohash-bucketing inputs the alias fast-path itself uses
  // (geohashEncode(shareLat, shareLng, ALIAS_GEOHASH_PRECISION)) — imported
  // indirectly isn't needed here since place_matching.ts's own
  // ALIAS_GEOHASH_PRECISION constant is exercised inside index.ts; this test
  // only needs a stable bucket, and geohashEncode is deterministic for the
  // same coordinates regardless of which module calls it.
  const { geohashEncode, normalizeForCompare, ALIAS_GEOHASH_PRECISION } = await import(
    "../_shared/place_matching.ts"
  );
  const geohash = geohashEncode(lat, lng, ALIAS_GEOHASH_PRECISION);

  assert(
    ALIAS_MIN_TRUST_CONFIDENCE > 0.1 && ALIAS_MIN_TRUST_CONFIDENCE < 0.9,
    "test fixture assumption: 0.1 below / 0.9 above the current ALIAS_MIN_TRUST_CONFIDENCE",
  );

  const { error: aliasErr } = await admin.from("merchant_aliases").insert({
    alias_text_normalized: normalizeForCompare(merchantName),
    geohash_bucket: geohash,
    canonical_place_id: decayedAliasPlaceId,
    canonical_name: merchantName,
    canonical_lat: lat,
    canonical_lng: lng,
    confidence: 0.1, // below ALIAS_MIN_TRUST_CONFIDENCE (0.25)
  });
  if (aliasErr) throw new Error(`failed to seed decayed alias: ${aliasErr.message}`);

  setMode("off"); // gate behavior is independent of merchant-intelligence mode.
  try {
    await insertTransaction({
      id: txId,
      share_location_lat: lat,
      share_location_lng: lng,
      llm_understanding: buildUnderstanding({ merchantName }),
    });

    let placesCallCount = 0;
    const mockFetch = makeMockFetch(
      [{ id: freshPlaceId, name: merchantName, lat, lng, types: ["cafe"] }],
      { onPlacesCall: () => placesCallCount++ },
    );
    const resp = await handleEnrichTransactionRequest(buildRequest(txId), {
      fetchFn: mockFetch,
    });
    const body = await resp.json();
    assertEquals(resp.status, 200);
    assertEquals(body.ok, true);
    assert(
      body.resolved_via !== "alias",
      "a below-floor alias hit must not resolve via the alias fast-path",
    );
    assert(placesCallCount > 0, "expected the decayed alias to fall through to a real Places call");

    const row = await fetchTransaction(txId);
    assertEquals(
      row.place_google_place_id,
      freshPlaceId,
      "should resolve via the mocked Places fallback, not the decayed alias's place",
    );
  } finally {
    await deleteTransaction(txId);
    await deleteMerchantAliasByPlaceId(decayedAliasPlaceId);
    await deleteMerchantAliasByPlaceId(freshPlaceId);
    setMode(undefined);
  }
});

Deno.test("alias gate: an at/above-floor alias hit is still trusted via the fast-path exactly as before", NET_TEST_OPTS, async () => {
  const runId = crypto.randomUUID().slice(0, 8);
  const txId = crypto.randomUUID();
  const merchantName = `Kedai Trusted Alias ${runId}`;
  const trustedAliasPlaceId = `place-trusted-alias-${runId}`;
  const lat = 3.16;
  const lng = 101.71;
  const { geohashEncode, normalizeForCompare, ALIAS_GEOHASH_PRECISION } = await import(
    "../_shared/place_matching.ts"
  );
  const geohash = geohashEncode(lat, lng, ALIAS_GEOHASH_PRECISION);

  const { error: aliasErr } = await admin.from("merchant_aliases").insert({
    alias_text_normalized: normalizeForCompare(merchantName),
    geohash_bucket: geohash,
    canonical_place_id: trustedAliasPlaceId,
    canonical_name: merchantName,
    canonical_lat: lat,
    canonical_lng: lng,
    confidence: 0.9, // comfortably at/above ALIAS_MIN_TRUST_CONFIDENCE (0.25)
  });
  if (aliasErr) throw new Error(`failed to seed trusted alias: ${aliasErr.message}`);

  setMode("off");
  try {
    await insertTransaction({
      id: txId,
      share_location_lat: lat,
      share_location_lng: lng,
      llm_understanding: buildUnderstanding({ merchantName }),
    });

    let placesCallCount = 0;
    const mockFetch = makeMockFetch([], { onPlacesCall: () => placesCallCount++ });
    const resp = await handleEnrichTransactionRequest(buildRequest(txId), {
      fetchFn: mockFetch,
    });
    const body = await resp.json();
    assertEquals(resp.status, 200);
    assertEquals(body.ok, true);
    assertEquals(body.resolved_via, "alias");
    assertEquals(placesCallCount, 0, "a trusted alias hit must never call Places");

    const row = await fetchTransaction(txId);
    assertEquals(row.place_google_place_id, trustedAliasPlaceId);
    assertEquals(row.place_status, "guess");
  } finally {
    await deleteTransaction(txId);
    await deleteMerchantAliasByPlaceId(trustedAliasPlaceId);
    setMode(undefined);
  }
});

// ---------------------------------------------------------------------------
// Receipt-first location: address on receipt → unbiased text search; merchant
// only + share GPS → nearby + location bias preserved.
// ---------------------------------------------------------------------------
Deno.test("receipt address: text search has no locationBias and nearby is skipped", NET_TEST_OPTS, async () => {
  const runId = crypto.randomUUID().slice(0, 8);
  const txId = crypto.randomUUID();
  const merchantName = `Receipt Addr Cafe ${runId}`;
  const placeId = `place-receipt-addr-${runId}`;
  const storeLat = 3.0738;
  const storeLng = 101.5183;

  setMode("off");
  try {
    await insertTransaction({
      id: txId,
      share_location_lat: 3.0,
      share_location_lng: 101.5,
      llm_understanding: buildUnderstanding({
        merchantName,
        addressText: "1 Utama Shopping Centre, Petaling Jaya",
        locationClues: ["1 Utama"],
      }),
    });

    const requests: Array<{ url: string; body: Record<string, unknown> }> = [];
    let nearbyCalls = 0;
    const mockFetch = makeMockFetch(
      [{ id: placeId, name: merchantName, lat: storeLat, lng: storeLng, types: ["cafe"] }],
      {
        onRequest: (url, body) => {
          requests.push({ url, body });
          if (url.includes("searchNearby")) nearbyCalls++;
        },
      },
    );
    const resp = await handleEnrichTransactionRequest(buildRequest(txId), {
      fetchFn: mockFetch,
    });
    assertEquals(resp.status, 200);

    assertEquals(nearbyCalls, 0, "nearby search must be skipped when receipt has address");
    const textCalls = requests.filter((r) => r.url.includes("searchText"));
    assert(textCalls.length > 0, "expected at least one text search");
    for (const call of textCalls) {
      assertEquals(
        call.body.locationBias,
        undefined,
        "text search must not bias toward upload GPS when receipt has address",
      );
    }

    const row = await fetchTransaction(txId);
    assertEquals(row.place_google_place_id, placeId);
    assertEquals(row.place_lat, storeLat);
  } finally {
    await deleteTransaction(txId);
    await deleteMerchantAliasByPlaceId(placeId);
    setMode(undefined);
  }
});

Deno.test("merchant only + share GPS: nearby search and locationBias still used", NET_TEST_OPTS, async () => {
  const runId = crypto.randomUUID().slice(0, 8);
  const txId = crypto.randomUUID();
  const merchantName = `Nearby Only Cafe ${runId}`;
  const placeId = `place-nearby-${runId}`;

  setMode("off");
  try {
    await insertTransaction({
      id: txId,
      share_location_lat: 3.15,
      share_location_lng: 101.7,
      llm_understanding: buildUnderstanding({ merchantName }),
    });

    const requests: Array<{ url: string; body: Record<string, unknown> }> = [];
    const mockFetch = makeMockFetch(
      [{ id: placeId, name: merchantName, lat: 3.15, lng: 101.7, types: ["cafe"] }],
      { onRequest: (url, body) => requests.push({ url, body }) },
    );
    const resp = await handleEnrichTransactionRequest(buildRequest(txId), {
      fetchFn: mockFetch,
    });
    assertEquals(resp.status, 200);

    assert(
      requests.some((r) => r.url.includes("searchNearby")),
      "expected nearby search when receipt has no address/clue",
    );
    const textCall = requests.find((r) => r.url.includes("searchText"));
    assertExists(textCall);
    assertExists(
      (textCall.body.locationBias as { circle?: unknown })?.circle,
      "text search should bias toward share GPS when no receipt location signal",
    );
  } finally {
    await deleteTransaction(txId);
    await deleteMerchantAliasByPlaceId(placeId);
    setMode(undefined);
  }
});

// ---------------------------------------------------------------------------
// Final cleanup: delete the test user (cascades to profiles -> any stray
// transactions this file's own per-test cleanup might have missed).
// ---------------------------------------------------------------------------
Deno.test("cleanup: delete the test user", NET_TEST_OPTS, async () => {
  if (!testUserId) return;
  const { error } = await admin.auth.admin.deleteUser(testUserId);
  if (error) {
    throw new Error(`failed to delete test user ${testUserId}: ${error.message}`);
  }
});
