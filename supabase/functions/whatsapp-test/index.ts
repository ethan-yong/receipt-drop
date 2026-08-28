import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// Bump here when Meta deprecates this version (currently within the
// supported v22-v25 window as of Aug 2026).
const GRAPH_API_VERSION = "v23.0";
const UPSTREAM_TIMEOUT_MS = 15_000;

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// Redacts all but the last 4 digits - the only form a recipient number may
// ever appear in a log line (never the token, never the full number).
function redactRecipient(recipient: string): string {
  if (recipient.length <= 4) return "*".repeat(recipient.length);
  return "*".repeat(recipient.length - 4) + recipient.slice(-4);
}

interface WhatsappTestConfig {
  accessToken: string;
  phoneNumberId: string;
  testRecipient: string;
}

// Reads WHATSAPP_ACCESS_TOKEN / WHATSAPP_PHONE_NUMBER_ID /
// WHATSAPP_TEST_RECIPIENT from Deno.env. Returns null if any is missing -
// caller maps that to 500 server_misconfigured. Never logs accessToken.
function loadConfigFromEnv(): WhatsappTestConfig | null {
  const accessToken = Deno.env.get("WHATSAPP_ACCESS_TOKEN");
  const phoneNumberId = Deno.env.get("WHATSAPP_PHONE_NUMBER_ID");
  const testRecipient = Deno.env.get("WHATSAPP_TEST_RECIPIENT");
  if (!accessToken || !phoneNumberId || !testRecipient) return null;
  return { accessToken, phoneNumberId, testRecipient };
}

// Maps Meta's raw error.code to a small, safe, snake_case vocabulary the
// client is allowed to see. Meta's actual code/subcode/type/fbtrace_id is
// logged server-side only, never returned in the response body.
function mapMetaErrorCode(metaCode: number | undefined): string {
  if (metaCode === 190) return "invalid_or_expired_token"; // OAuthException
  if (metaCode === 131030 || metaCode === 131026) return "invalid_recipient";
  if (metaCode === 100) return "invalid_phone_number_id";
  return "meta_api_rejected";
}

type SendTemplateResult =
  | { ok: true; messageId: string }
  | { ok: false; errorCode: string };

async function sendHelloWorldTemplate(
  cfg: WhatsappTestConfig,
  fetchFn: typeof fetch,
): Promise<SendTemplateResult> {
  const url =
    `https://graph.facebook.com/${GRAPH_API_VERSION}/${cfg.phoneNumberId}/messages`;
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), UPSTREAM_TIMEOUT_MS);
  try {
    const resp = await fetchFn(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${cfg.accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        messaging_product: "whatsapp",
        to: cfg.testRecipient,
        type: "template",
        template: { name: "hello_world", language: { code: "en_US" } },
      }),
      signal: controller.signal,
    });

    let json: Record<string, unknown>;
    try {
      json = await resp.json();
    } catch {
      console.error(
        `whatsapp-test: unexpected non-JSON Meta response, status=${resp.status}`,
      );
      return { ok: false, errorCode: "unexpected_upstream_response" };
    }

    if (!resp.ok) {
      const err = json.error as
        | {
          message?: string;
          type?: string;
          code?: number;
          error_subcode?: number;
          fbtrace_id?: string;
        }
        | undefined;
      console.error(
        `whatsapp-test: Meta API rejected (status=${resp.status}) code=${err?.code} ` +
          `subcode=${err?.error_subcode} type=${err?.type} fbtrace_id=${err?.fbtrace_id} ` +
          `recipient=${redactRecipient(cfg.testRecipient)}`,
      );
      return { ok: false, errorCode: mapMetaErrorCode(err?.code) };
    }

    const messageId =
      (json.messages as Array<{ id?: string }> | undefined)?.[0]?.id;
    if (!messageId) {
      console.error(
        `whatsapp-test: 200 response but no messages[0].id - shape=${
          JSON.stringify(json).slice(0, 300)
        }`,
      );
      return { ok: false, errorCode: "unexpected_upstream_response" };
    }

    console.log(
      `whatsapp-test: sent hello_world to ${
        redactRecipient(cfg.testRecipient)
      } - message_id=${messageId}`,
    );
    return { ok: true, messageId };
  } catch (err) {
    if (err instanceof Error && err.name === "AbortError") {
      console.error("whatsapp-test: upstream timeout calling Graph API");
      return { ok: false, errorCode: "upstream_timeout" };
    }
    console.error(`whatsapp-test: upstream unreachable - ${String(err)}`);
    return { ok: false, errorCode: "upstream_unreachable" };
  } finally {
    clearTimeout(timeoutId);
  }
}

export async function handleWhatsappTestRequest(
  req: Request,
  deps?: { fetchFn?: typeof fetch; config?: WhatsappTestConfig | null },
): Promise<Response> {
  const fetchFn = deps?.fetchFn ?? fetch;

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
    return jsonResponse({ ok: false, error: "unauthorized" }, 401);
  }

  // Body is intentionally ignored beyond a defensive parse - recipient and
  // template are fixed server-side (see loadConfigFromEnv), never
  // client-controlled. An empty body is valid; only malformed JSON *with*
  // content is rejected, to fail loudly on an obviously wrong caller.
  const rawBody = await req.text();
  if (rawBody.trim().length > 0) {
    try {
      JSON.parse(rawBody);
    } catch {
      return jsonResponse({ ok: false, error: "invalid_json" }, 400);
    }
  }

  const config = deps?.config !== undefined ? deps.config : loadConfigFromEnv();
  if (!config) {
    console.error(
      "whatsapp-test: missing WHATSAPP_ACCESS_TOKEN/WHATSAPP_PHONE_NUMBER_ID/WHATSAPP_TEST_RECIPIENT",
    );
    return jsonResponse({ ok: false, error: "server_misconfigured" }, 500);
  }

  const result = await sendHelloWorldTemplate(config, fetchFn);
  if (!result.ok) {
    return jsonResponse({ ok: false, error: result.errorCode }, 502);
  }
  return jsonResponse({ ok: true, message_id: result.messageId }, 200);
}

if (import.meta.main) {
  Deno.serve((req) => handleWhatsappTestRequest(req));
}
