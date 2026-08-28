// Deno integration tests for whatsapp-test's `handleWhatsappTestRequest`
// (extracted from the file's top-level `Deno.serve(...)` - see the
// `import.meta.main` guard at the bottom of index.ts). Mirrors
// enrich-transaction/index.test.ts: exercises the REAL local Supabase Auth
// (no mocking of JWT verification) with only the Meta Graph API `fetch`
// call mocked. Unlike enrich-transaction, this function never touches
// Postgres beyond `auth.getUser()`, so there are no DB fixtures to manage.
//
// Requires a running local Supabase stack (`supabase status` to confirm;
// the well-known local CLI default URL/keys are hardcoded below - override
// via TEST_SUPABASE_* env vars if your local stack uses non-default
// ports/keys).
//
// Run with:
//   deno test --allow-net --allow-env supabase/functions/whatsapp-test/index.test.ts
// (--allow-net: real HTTP calls to the local Supabase Auth API; --allow-env:
// reads/writes SUPABASE_URL/SUPABASE_ANON_KEY via Deno.env. The Meta Graph
// API call is always mocked via `deps.fetchFn` - no real network call to
// graph.facebook.com ever happens in this file.)

import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { handleWhatsappTestRequest } from "./index.ts";

// ---------------------------------------------------------------------------
// Local dev stack connection info - same well-known `supabase init` CLI
// defaults used by enrich-transaction/index.test.ts (public fixture values
// baked into every local Supabase CLI project, not a secret).
// ---------------------------------------------------------------------------
const SUPABASE_URL = Deno.env.get("TEST_SUPABASE_URL") ??
  "http://127.0.0.1:54321";
const ANON_KEY = Deno.env.get("TEST_SUPABASE_ANON_KEY") ??
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0";
const SERVICE_ROLE_KEY = Deno.env.get("TEST_SUPABASE_SERVICE_ROLE_KEY") ??
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU";

// The handler under test reads these itself via `Deno.env.get(...)` - a bare
// `deno test` process has neither, unlike `supabase functions serve`'s
// injected environment, so this file must set them up front.
Deno.env.set("SUPABASE_URL", SUPABASE_URL);
Deno.env.set("SUPABASE_ANON_KEY", ANON_KEY);

const admin: SupabaseClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

// Every Deno.test below makes real network calls (Auth over HTTP via
// supabase-js) - sanitizers otherwise flag normal keep-alive connection
// reuse across tests as a "leak".
const NET_TEST_OPTS = { sanitizeOps: false, sanitizeResources: false } as const;

let testUserId = "";
let testAccessToken = "";

const FAKE_CONFIG = {
  accessToken: "fake-token",
  phoneNumberId: "fake-phone-number-id",
  testRecipient: "60123456789",
};

function buildRequest(
  opts?: { auth?: string; body?: string },
): Request {
  const headers: Record<string, string> = {};
  if (opts?.auth === undefined) {
    headers.Authorization = `Bearer ${testAccessToken}`;
  } else if (opts.auth) {
    headers.Authorization = opts.auth;
  }
  return new Request("http://localhost/", {
    method: "POST",
    headers,
    body: opts?.body,
  });
}

function makeMockFetch(
  handler: (url: string, body: Record<string, unknown>) => Response,
): typeof fetch {
  return ((input: RequestInfo | URL, init?: RequestInit) => {
    const url = typeof input === "string"
      ? input
      : input instanceof URL
      ? input.toString()
      : input.url;
    if (!url.includes("graph.facebook.com")) {
      throw new Error(`mockFetch: unexpected non-Graph call to ${url}`);
    }
    const body = init?.body && typeof init.body === "string"
      ? JSON.parse(init.body)
      : {};
    return Promise.resolve(handler(url, body));
  }) as typeof fetch;
}

// ---------------------------------------------------------------------------
// Setup / cleanup
// ---------------------------------------------------------------------------

Deno.test(
  "setup: create a real local-Auth test user and sign in",
  NET_TEST_OPTS,
  async () => {
    const email = `whatsapp-test-${crypto.randomUUID()}@example.com`;
    const password = "test-password-12345!";
    const { data: created, error: createError } = await admin.auth.admin
      .createUser({ email, password, email_confirm: true });
    if (createError || !created.user) {
      throw new Error(`failed to create test user: ${createError?.message}`);
    }
    testUserId = created.user.id;

    const anon = createClient(SUPABASE_URL, ANON_KEY);
    const { data: signedIn, error: signInError } = await anon.auth
      .signInWithPassword({ email, password });
    if (signInError || !signedIn.session) {
      throw new Error(`failed to sign in test user: ${signInError?.message}`);
    }
    testAccessToken = signedIn.session.access_token;
    assertExists(testAccessToken);
  },
);

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

Deno.test(
  "unauthenticated: missing Authorization returns 401",
  NET_TEST_OPTS,
  async () => {
    const resp = await handleWhatsappTestRequest(
      buildRequest({ auth: "" }),
      { config: FAKE_CONFIG },
    );
    assertEquals(resp.status, 401);
    const body = await resp.json();
    assertEquals(body.ok, false);
    assertEquals(body.error, "unauthorized");
  },
);

Deno.test(
  "unauthenticated: garbage bearer token returns 401",
  NET_TEST_OPTS,
  async () => {
    const resp = await handleWhatsappTestRequest(
      buildRequest({ auth: "Bearer not-a-real-jwt" }),
      { config: FAKE_CONFIG },
    );
    assertEquals(resp.status, 401);
  },
);

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

Deno.test(
  "config missing: 500 server_misconfigured, Meta never called",
  NET_TEST_OPTS,
  async () => {
    let called = false;
    const mockFetch = makeMockFetch(() => {
      called = true;
      return new Response("{}", { status: 200 });
    });
    const resp = await handleWhatsappTestRequest(buildRequest(), {
      config: null,
      fetchFn: mockFetch,
    });
    assertEquals(resp.status, 500);
    const body = await resp.json();
    assertEquals(body.ok, false);
    assertEquals(body.error, "server_misconfigured");
    assertEquals(called, false);
  },
);

// ---------------------------------------------------------------------------
// Success
// ---------------------------------------------------------------------------

Deno.test(
  "success: 200 with sanitized {ok:true, message_id}, request shape matches Meta's docs",
  NET_TEST_OPTS,
  async () => {
    let capturedBody: Record<string, unknown> | undefined;
    const mockFetch = makeMockFetch((_url, body) => {
      capturedBody = body;
      return new Response(
        JSON.stringify({
          messaging_product: "whatsapp",
          contacts: [
            { input: FAKE_CONFIG.testRecipient, wa_id: FAKE_CONFIG.testRecipient },
          ],
          messages: [{ id: "wamid.TEST123" }],
        }),
        { status: 200 },
      );
    });
    const resp = await handleWhatsappTestRequest(buildRequest(), {
      config: FAKE_CONFIG,
      fetchFn: mockFetch,
    });
    assertEquals(resp.status, 200);
    const body = await resp.json();
    assertEquals(body.ok, true);
    assertEquals(body.message_id, "wamid.TEST123");
    // No token leakage:
    assertEquals(JSON.stringify(body).includes(FAKE_CONFIG.accessToken), false);

    assertEquals(capturedBody?.messaging_product, "whatsapp");
    assertEquals(capturedBody?.to, FAKE_CONFIG.testRecipient);
    assertEquals(capturedBody?.type, "template");
    assertEquals(
      (capturedBody?.template as Record<string, unknown>)?.name,
      "hello_world",
    );
  },
);

// ---------------------------------------------------------------------------
// Meta rejections
// ---------------------------------------------------------------------------

Deno.test(
  "meta rejection: expired token (code 190) maps to invalid_or_expired_token, 502, no raw Meta error leaked",
  NET_TEST_OPTS,
  async () => {
    const mockFetch = makeMockFetch(() =>
      new Response(
        JSON.stringify({
          error: {
            message: "Error validating access token",
            type: "OAuthException",
            code: 190,
            fbtrace_id: "AbCdEf",
          },
        }),
        { status: 401 },
      )
    );
    const resp = await handleWhatsappTestRequest(buildRequest(), {
      config: FAKE_CONFIG,
      fetchFn: mockFetch,
    });
    assertEquals(resp.status, 502);
    const body = await resp.json();
    assertEquals(body.ok, false);
    assertEquals(body.error, "invalid_or_expired_token");
    assertEquals(JSON.stringify(body).includes("fbtrace_id"), false);
    assertEquals(JSON.stringify(body).includes("AbCdEf"), false);
  },
);

Deno.test(
  "meta rejection: recipient not allowed (code 131030) maps to invalid_recipient",
  NET_TEST_OPTS,
  async () => {
    const mockFetch = makeMockFetch(() =>
      new Response(
        JSON.stringify({
          error: {
            message: "Recipient not in allowed list",
            type: "OAuthException",
            code: 131030,
          },
        }),
        { status: 400 },
      )
    );
    const resp = await handleWhatsappTestRequest(buildRequest(), {
      config: FAKE_CONFIG,
      fetchFn: mockFetch,
    });
    assertEquals(resp.status, 502);
    const body = await resp.json();
    assertEquals(body.error, "invalid_recipient");
  },
);

Deno.test(
  "meta rejection: invalid phone number id (code 100) maps to invalid_phone_number_id",
  NET_TEST_OPTS,
  async () => {
    const mockFetch = makeMockFetch(() =>
      new Response(
        JSON.stringify({
          error: {
            message: "Unsupported post request",
            type: "GraphMethodException",
            code: 100,
          },
        }),
        { status: 400 },
      )
    );
    const resp = await handleWhatsappTestRequest(buildRequest(), {
      config: FAKE_CONFIG,
      fetchFn: mockFetch,
    });
    assertEquals((await resp.json()).error, "invalid_phone_number_id");
  },
);

Deno.test(
  "meta rejection: unrecognized error code falls back to meta_api_rejected",
  NET_TEST_OPTS,
  async () => {
    const mockFetch = makeMockFetch(() =>
      new Response(
        JSON.stringify({
          error: { message: "Something else", type: "Other", code: 999 },
        }),
        { status: 400 },
      )
    );
    const resp = await handleWhatsappTestRequest(buildRequest(), {
      config: FAKE_CONFIG,
      fetchFn: mockFetch,
    });
    assertEquals((await resp.json()).error, "meta_api_rejected");
  },
);

// ---------------------------------------------------------------------------
// Network / shape failures
// ---------------------------------------------------------------------------

Deno.test(
  "network failure: fetch throws maps to upstream_unreachable",
  NET_TEST_OPTS,
  async () => {
    const mockFetch = (() => {
      throw new TypeError("network down");
    }) as unknown as typeof fetch;
    const resp = await handleWhatsappTestRequest(buildRequest(), {
      config: FAKE_CONFIG,
      fetchFn: mockFetch,
    });
    assertEquals(resp.status, 502);
    assertEquals((await resp.json()).error, "upstream_unreachable");
  },
);

Deno.test(
  "timeout: AbortError maps to upstream_timeout",
  NET_TEST_OPTS,
  async () => {
    const mockFetch = (() => {
      const err = new DOMException("aborted", "AbortError");
      return Promise.reject(err);
    }) as unknown as typeof fetch;
    const resp = await handleWhatsappTestRequest(buildRequest(), {
      config: FAKE_CONFIG,
      fetchFn: mockFetch,
    });
    assertEquals(resp.status, 502);
    assertEquals((await resp.json()).error, "upstream_timeout");
  },
);

Deno.test(
  "unexpected shape: 200 response missing messages[0].id maps to unexpected_upstream_response",
  NET_TEST_OPTS,
  async () => {
    const mockFetch = makeMockFetch(() =>
      new Response(JSON.stringify({ messaging_product: "whatsapp" }), {
        status: 200,
      })
    );
    const resp = await handleWhatsappTestRequest(buildRequest(), {
      config: FAKE_CONFIG,
      fetchFn: mockFetch,
    });
    assertEquals((await resp.json()).error, "unexpected_upstream_response");
  },
);

// ---------------------------------------------------------------------------
// Request validation / method
// ---------------------------------------------------------------------------

Deno.test(
  "malformed request body: invalid JSON with content returns 400",
  NET_TEST_OPTS,
  async () => {
    const resp = await handleWhatsappTestRequest(
      buildRequest({ body: "{not valid json" }),
      { config: FAKE_CONFIG },
    );
    assertEquals(resp.status, 400);
    assertEquals((await resp.json()).error, "invalid_json");
  },
);

Deno.test(
  "empty body: still succeeds (body is optional/ignored)",
  NET_TEST_OPTS,
  async () => {
    const mockFetch = makeMockFetch(() =>
      new Response(
        JSON.stringify({ messages: [{ id: "wamid.EMPTYBODY" }] }),
        { status: 200 },
      )
    );
    const resp = await handleWhatsappTestRequest(
      buildRequest({ body: "" }),
      { config: FAKE_CONFIG, fetchFn: mockFetch },
    );
    assertEquals(resp.status, 200);
  },
);

Deno.test(
  "method not allowed: GET returns 405",
  NET_TEST_OPTS,
  async () => {
    const resp = await handleWhatsappTestRequest(
      new Request("http://localhost/", { method: "GET" }),
    );
    assertEquals(resp.status, 405);
  },
);

// ---------------------------------------------------------------------------
// Cleanup
// ---------------------------------------------------------------------------

Deno.test(
  "cleanup: delete the test user",
  NET_TEST_OPTS,
  async () => {
    if (!testUserId) return;
    const { error } = await admin.auth.admin.deleteUser(testUserId);
    if (error) {
      throw new Error(`failed to delete test user ${testUserId}: ${error.message}`);
    }
  },
);
