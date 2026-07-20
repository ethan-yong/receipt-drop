import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { cfAccessHeaders } from "../_shared/cf_access.ts";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const ALLOWED_MIME_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);
// ocr-api's /ocr now runs Tesseract (up to ~20s across its confidence-based
// retry pass) AND the synchronous LLM understanding step (up to
// LLM_TIMEOUT_SECONDS=25s, see services/ocr-api/ocr_api/receipt_understanding.py)
// in the same request — this must stay comfortably above OCR + LLM combined,
// not just the LLM step alone (contrast UNDERSTAND_TIMEOUT_MS in
// _shared/receipt_understanding.ts, which only wraps the LLM-only /understand
// call). A too-short timeout here aborts before ocr-api can ever respond, so
// the client gets nothing back at all — not even the raw OCR text.
const UPSTREAM_TIMEOUT_MS = 60_000;

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !supabaseAnonKey) {
    return jsonResponse({ error: "server_misconfigured" }, 500);
  }

  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: { user }, error: userError } = await supabase.auth.getUser();
  if (userError || !user) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }

  const contentType = req.headers.get("Content-Type") ?? "";
  if (!ALLOWED_MIME_TYPES.has(contentType)) {
    return jsonResponse({ error: "unsupported_media_type" }, 400);
  }

  const imageBytes = await req.arrayBuffer();
  if (imageBytes.byteLength === 0) {
    return jsonResponse({ error: "empty_body" }, 400);
  }

  const ocrServiceUrl = Deno.env.get("OCR_SERVICE_URL");
  const ocrServiceSecret = Deno.env.get("OCR_SERVICE_SECRET");
  if (!ocrServiceUrl || !ocrServiceSecret) {
    return jsonResponse({ error: "server_misconfigured" }, 500);
  }
  // Optional — only set in production, where ocr.receipt-drop.org is gated by
  // Cloudflare Access on top of X-OCR-Secret. See docs/decisions.md.
  const cfAccessClientId = Deno.env.get("CF_ACCESS_CLIENT_ID");
  const cfAccessClientSecret = Deno.env.get("CF_ACCESS_CLIENT_SECRET");

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), UPSTREAM_TIMEOUT_MS);

  try {
    const resp = await fetch(`${ocrServiceUrl.replace(/\/+$/, "")}/ocr`, {
      method: "POST",
      headers: {
        "Content-Type": contentType,
        "X-OCR-Secret": ocrServiceSecret,
        ...cfAccessHeaders(cfAccessClientId, cfAccessClientSecret),
      },
      body: imageBytes,
      signal: controller.signal,
    });

    const json = await resp.json();
    return jsonResponse(json, resp.ok ? 200 : 502);
  } catch (err) {
    if (err instanceof Error && err.name === "AbortError") {
      return jsonResponse({ error: "upstream_timeout" }, 504);
    }
    return jsonResponse({ error: "upstream_unreachable" }, 502);
  } finally {
    clearTimeout(timeoutId);
  }
});
