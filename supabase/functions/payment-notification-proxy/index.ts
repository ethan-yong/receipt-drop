import { cfAccessHeaders } from "../_shared/cf_access.ts";
import { isValidPaymentNotificationSecret } from "../_shared/payment_notification_auth.ts";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "x-payment-notification-secret, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// services/ocr-api's PAYMENT_NOTIFICATION_LLM_TIMEOUT_SECONDS is 8s — this
// must stay comfortably above that (network + ocr-api's own overhead), but
// well under Cloudflare's ~100s tunnel ceiling. The native caller
// (PaymentNotificationClient.kt) has its own independent ~8s client-side
// timeout too; either side timing out first is fine, both degrade the same
// way (no overlay shown, no transaction created).
const UPSTREAM_TIMEOUT_MS = 15_000;

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

  // Not a Supabase user JWT — see supabase/config.toml's verify_jwt=false
  // entry for this function and _shared/payment_notification_auth.ts.
  const providedSecret = req.headers.get("X-Payment-Notification-Secret");
  if (!isValidPaymentNotificationSecret(providedSecret)) {
    console.warn("payment-notification-proxy: unauthorized (bad or missing secret)");
    return jsonResponse({ error: "unauthorized" }, 401);
  }
  console.log("payment-notification-proxy: invoked");

  let body: {
    notification_text?: unknown;
    source_package?: unknown;
    posted_at?: unknown;
  };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const notificationText = typeof body.notification_text === "string"
    ? body.notification_text
    : "";
  if (!notificationText.trim()) {
    return jsonResponse({ error: "empty_notification_text" }, 400);
  }
  const sourcePackage = typeof body.source_package === "string"
    ? body.source_package
    : null;
  const postedAt = typeof body.posted_at === "string" ? body.posted_at : null;

  const ocrServiceUrl = Deno.env.get("OCR_SERVICE_URL");
  const ocrServiceSecret = Deno.env.get("OCR_SERVICE_SECRET");
  if (!ocrServiceUrl || !ocrServiceSecret) {
    console.error("payment-notification-proxy: OCR_SERVICE_URL/SECRET missing");
    return jsonResponse({ error: "server_misconfigured" }, 500);
  }
  const cfAccessClientId = Deno.env.get("CF_ACCESS_CLIENT_ID");
  const cfAccessClientSecret = Deno.env.get("CF_ACCESS_CLIENT_SECRET");

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), UPSTREAM_TIMEOUT_MS);

  try {
    const resp = await fetch(
      `${ocrServiceUrl.replace(/\/+$/, "")}/understand-payment-notification`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-OCR-Secret": ocrServiceSecret,
          ...cfAccessHeaders(cfAccessClientId, cfAccessClientSecret),
        },
        body: JSON.stringify({
          notification_text: notificationText,
          source_package: sourcePackage,
          posted_at: postedAt,
        }),
        signal: controller.signal,
      },
    );

    const json = await resp.json();
    if (!resp.ok) {
      console.error(
        `payment-notification-proxy: upstream http_${resp.status}`,
      );
    }
    return jsonResponse(json, resp.status);
  } catch (err) {
    if (err instanceof Error && err.name === "AbortError") {
      console.error("payment-notification-proxy: upstream_timeout");
      return jsonResponse({ error: "upstream_timeout" }, 504);
    }
    console.error(`payment-notification-proxy: upstream_unreachable: ${err}`);
    return jsonResponse({ error: "upstream_unreachable" }, 502);
  } finally {
    clearTimeout(timeoutId);
  }
});
