/**
 * Curate spending-insight candidates into 1-3 friendly sentences.
 *
 * Receives a small structured candidate pool from the client (never raw
 * transactions / OCR text), calls ocr-api POST /curate-insights, validates
 * the response against the closed type vocabulary, persists to
 * spending_insights (owner JWT), and returns the new rows in the response
 * for the client to mirror locally.
 *
 * Soft-launch: clients may skip this entirely via kInsightsUseTemplateFallback.
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { cfAccessHeaders } from "../_shared/cf_access.ts";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const ALLOWED_TYPES = new Set([
  "spending_spike",
  "category_shift",
  "habit",
  "streak",
  "forecast",
]);

const UPSTREAM_TIMEOUT_MS = 55_000;
const MAX_INSIGHTS = 3;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !supabaseAnonKey) {
    return jsonResponse({ error: "server_misconfigured" }, 500);
  }

  const client = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const {
    data: { user },
    error: userError,
  } = await client.auth.getUser();
  if (userError || !user) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }

  let body: { candidates?: unknown };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const candidates = sanitizeCandidates(body.candidates);
  if (candidates.length === 0) {
    return jsonResponse({ insights: [] });
  }

  const ocrServiceUrl = Deno.env.get("OCR_SERVICE_URL");
  const ocrServiceSecret = Deno.env.get("OCR_SERVICE_SECRET");
  if (!ocrServiceUrl || !ocrServiceSecret) {
    return jsonResponse({ error: "server_misconfigured" }, 500);
  }

  const cfAccessClientId = Deno.env.get("CF_ACCESS_CLIENT_ID");
  const cfAccessClientSecret = Deno.env.get("CF_ACCESS_CLIENT_SECRET");

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), UPSTREAM_TIMEOUT_MS);

  let curatedRaw: unknown;
  try {
    const resp = await fetch(
      `${ocrServiceUrl.replace(/\/+$/, "")}/curate-insights`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-OCR-Secret": ocrServiceSecret,
          ...cfAccessHeaders(cfAccessClientId, cfAccessClientSecret),
        },
        body: JSON.stringify({ candidates }),
        signal: controller.signal,
      },
    );
    if (!resp.ok) {
      return jsonResponse({ error: "curator_upstream_error" }, 502);
    }
    curatedRaw = await resp.json();
  } catch {
    return jsonResponse({ error: "curator_timeout" }, 504);
  } finally {
    clearTimeout(timeoutId);
  }

  const curated = validateCurated(curatedRaw, candidates);
  if (curated.length === 0) {
    return jsonResponse({ insights: [] });
  }

  const rowsToInsert = curated.map((c, i) => ({
    user_id: user.id,
    insight_type: c.type,
    fact_key: c.fact_key,
    body: c.body,
    rank: i,
    dismissed: false,
    facts: c.facts ?? null,
  }));

  const { data: inserted, error: insertError } = await client
    .from("spending_insights")
    .insert(rowsToInsert)
    .select("id, insight_type, fact_key, body, rank, created_at, dismissed");

  if (insertError || !inserted) {
    // Soft degrade — return validated content with ephemeral ids so the
    // client can still show something this session without persistence.
    return jsonResponse({
      insights: curated.map((c, i) => ({
        id: crypto.randomUUID(),
        type: c.type,
        fact_key: c.fact_key,
        body: c.body,
        rank: i,
        created_at: new Date().toISOString(),
        dismissed: false,
      })),
    });
  }

  return jsonResponse({
    insights: inserted.map((row) => ({
      id: row.id,
      type: row.insight_type,
      fact_key: row.fact_key,
      body: row.body,
      rank: row.rank,
      created_at: row.created_at,
      dismissed: row.dismissed === true,
    })),
  });
});

type Candidate = {
  type: string;
  fact_key: string;
  facts: Record<string, unknown>;
  severity: number;
  template_hint?: string;
};

function sanitizeCandidates(raw: unknown): Candidate[] {
  if (!Array.isArray(raw)) return [];
  const out: Candidate[] = [];
  for (const item of raw) {
    if (!item || typeof item !== "object") continue;
    const rec = item as Record<string, unknown>;
    const type = typeof rec.type === "string" ? rec.type : "";
    const factKey =
      typeof rec.fact_key === "string"
        ? rec.fact_key
        : typeof rec.factKey === "string"
        ? rec.factKey
        : "";
    if (!ALLOWED_TYPES.has(type) || !factKey) continue;
    const facts =
      rec.facts && typeof rec.facts === "object" && !Array.isArray(rec.facts)
        ? (rec.facts as Record<string, unknown>)
        : {};
    const severity = typeof rec.severity === "number" ? rec.severity : 0;
    const hint =
      typeof rec.template_hint === "string"
        ? rec.template_hint
        : typeof rec.templateHint === "string"
        ? rec.templateHint
        : undefined;
    out.push({
      type,
      fact_key: factKey,
      facts,
      severity,
      template_hint: hint,
    });
  }
  return out.slice(0, 20);
}

function validateCurated(
  raw: unknown,
  candidates: Candidate[],
): Array<{
  type: string;
  fact_key: string;
  body: string;
  facts?: Record<string, unknown>;
}> {
  if (!raw || typeof raw !== "object") return [];
  const list = (raw as { insights?: unknown }).insights;
  if (!Array.isArray(list)) return [];

  const byFact = new Map(candidates.map((c) => [c.fact_key, c]));
  const out: Array<{
    type: string;
    fact_key: string;
    body: string;
    facts?: Record<string, unknown>;
  }> = [];
  const seen = new Set<string>();

  for (const item of list) {
    if (!item || typeof item !== "object") continue;
    const rec = item as Record<string, unknown>;
    const type = typeof rec.type === "string" ? rec.type : "";
    const factKey =
      typeof rec.fact_key === "string"
        ? rec.fact_key
        : typeof rec.factKey === "string"
        ? rec.factKey
        : "";
    const body = typeof rec.body === "string" ? rec.body.trim() : "";
    if (!ALLOWED_TYPES.has(type) || !factKey || !body) continue;
    if (seen.has(factKey)) continue;
    const source = byFact.get(factKey);
    if (!source || source.type !== type) continue; // no fabricated facts
    seen.add(factKey);
    out.push({ type, fact_key: factKey, body, facts: source.facts });
    if (out.length >= MAX_INSIGHTS) break;
  }
  return out;
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
