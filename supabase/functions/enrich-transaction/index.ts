import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  ALIAS_GEOHASH_PRECISION,
  ALIAS_MIN_TRUST_CONFIDENCE,
  ALIAS_SAVE_CONFIDENCE_THRESHOLD,
  SEARCH_RADIUS_METERS,
  geohashEncode,
  isUsableMerchantText,
  normalizeForCompare,
  scoreCandidate,
} from "../_shared/place_matching.ts";
import {
  decideMerchantResolution,
  deriveBrandCandidates,
  type MerchantCandidateForScoring,
} from "../_shared/merchant_resolution.ts";
import {
  adjustScoreForTypeMatch,
  buildLlmTextQueries,
  callReceiptUnderstanding,
  hasReceiptLocationSignal,
  parseReceiptUnderstanding,
  resolveIncludedTypes,
  type ReceiptUnderstanding,
} from "../_shared/receipt_understanding.ts";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function normalizeMerchant(raw: string | null | undefined): string | null {
  if (raw == null) return null;
  const collapsed = String(raw).trim().replace(/\s+/g, " ");
  return collapsed.length === 0 ? null : collapsed;
}

type MerchantIntelligenceMode = "off" | "shadow" | "on";

/// Reads MERCHANT_INTELLIGENCE_MODE, defaulting to "off" — the safe default —
/// for anything unset or unrecognized. "off": no merchant/location
/// reconciliation at all (today's behavior, unchanged). "shadow": scores a
/// decision via decideMerchantResolution() and logs it, but never calls
/// reconcile_merchant_resolution. "on": additionally calls
/// reconcile_merchant_resolution to persist the decision. A later rollout
/// task is responsible for flipping this per environment; this task must not
/// change production behavior on its own.
function getMerchantIntelligenceMode(): MerchantIntelligenceMode {
  const raw = Deno.env.get("MERCHANT_INTELLIGENCE_MODE");
  return raw === "shadow" || raw === "on" ? raw : "off";
}

function stripPlacesResourcePrefix(id: string): string {
  return id.replace(/^places\//, "");
}

function placeDisplayName(first: {
  displayName?: { text?: string } | string;
}): string | null {
  const d = first.displayName;
  if (d == null) return null;
  if (typeof d === "string") return d;
  return d.text ?? null;
}

/// Extends `merchant_aliases`' write-back (docs/plans/
/// 2026-07-23-feedback-learning-system.md) with a second trigger: an
/// explicit user correction, not only an algorithmic >=0.85-confidence
/// auto-resolve. Looks up this transaction's synced `user_field_corrections`
/// row for the given [correctionType] (there's at most one merchant
/// correction per transaction — the confirm sheet only fires once per
/// field) and, if present, upserts via `upsert_merchant_alias_from_correction`
/// (its own corroboration-gate tiering lives entirely in that SQL function).
/// Best-effort: any failure here must never affect this transaction's own
/// already-saved enrichment result.
async function maybeWriteBackMerchantAliasFromCorrection(
  client: ReturnType<typeof createClient>,
  transactionId: string,
  userId: string,
  correctionType: "user_locked" | "free_text",
  place: {
    id: string | null | undefined;
    name: string | null;
    lat: number | null;
    lng: number | null;
  },
  shareLat: number | null | undefined,
  shareLng: number | null | undefined,
): Promise<void> {
  if (
    typeof shareLat !== "number" ||
    typeof shareLng !== "number" ||
    !place.id ||
    !place.name
  ) {
    return;
  }
  try {
    const { data: corrections } = await client
      .from("user_field_corrections")
      .select("predicted_value, confirmed_value, confidence")
      .eq("transaction_id", transactionId)
      .eq("user_id", userId)
      .eq("field", "merchant")
      .eq("correction_type", correctionType)
      .limit(1);
    const correction = Array.isArray(corrections) ? corrections[0] : null;
    if (!correction) return;

    // The alias key is the text a *future* garbled OCR read should match
    // against: for a picker override the user picked a place without
    // retyping the name, so the original OCR guess is still the right key;
    // for a free-text rename, the user's own corrected text is the name
    // future scans of this merchant should resolve via.
    const aliasText = correctionType === "user_locked"
      ? correction.predicted_value
      : correction.confirmed_value;
    if (!isUsableMerchantText(aliasText)) return;

    const ocrConfidence = typeof correction.confidence === "number"
      ? correction.confidence
      : null;

    await client.rpc("upsert_merchant_alias_from_correction", {
      p_alias_text: normalizeForCompare(aliasText),
      p_geohash: geohashEncode(shareLat, shareLng, ALIAS_GEOHASH_PRECISION),
      p_place_id: place.id,
      p_name: place.name,
      p_lat: place.lat,
      p_lng: place.lng,
      p_correction_type: correctionType,
      p_transaction_id: transactionId,
      p_ocr_confidence: ocrConfidence,
    });
  } catch {
    // Non-fatal — see function doc comment above.
  }
}

async function markPlacesFailure(
  client: ReturnType<typeof createClient>,
  transactionId: string,
  userId: string,
  merchantNormalized: string | null,
): Promise<boolean> {
  const { error } = await client
    .from("transactions")
    .update({
      pipeline_status: "failed_enrichment",
      merchant_normalized: merchantNormalized,
    })
    .eq("id", transactionId)
    .eq("user_id", userId);
  return error == null;
}

/// Extracted from the top-level `Deno.serve(...)` call (structural-only
/// change, see `if (import.meta.main)` guard at the bottom of this file) so
/// `index.test.ts` can `import { handleEnrichTransactionRequest }` and drive
/// the full handler in-process — no real HTTP server, no real network calls
/// to Google Places — without binding a port or hitting production APIs.
/// Mirrors the `fetchFn: typeof fetch = fetch` injection pattern already
/// used by `callReceiptUnderstanding` (receipt_understanding.ts): `deps` is
/// optional and defaults every injectable to its real implementation, so
/// this is a no-op for the actual Supabase Edge Runtime invocation in
/// production/local `supabase functions serve`.
export async function handleEnrichTransactionRequest(
  req: Request,
  deps?: { fetchFn?: typeof fetch },
): Promise<Response> {
  const fetchFn = deps?.fetchFn ?? fetch;
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !supabaseAnonKey) {
    return new Response(JSON.stringify({ error: "server_misconfigured" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: { user }, error: userError } = await supabase.auth.getUser();
  if (userError || !user) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  let bodyJson: Record<string, unknown>;
  try {
    bodyJson = (await req.json()) as Record<string, unknown>;
  } catch {
    return new Response(JSON.stringify({ error: "invalid_json" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const transactionId = bodyJson["transaction_id"];
  if (!transactionId || typeof transactionId !== "string") {
    return new Response(JSON.stringify({ error: "bad_request" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const { data: row, error: rowError } = await supabase
    .from("transactions")
    .select("*")
    .eq("id", transactionId)
    .single();

  if (rowError || !row) {
    return new Response(JSON.stringify({ error: "not_found" }), {
      status: 404,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  if (row.user_id !== user.id) {
    return new Response(JSON.stringify({ error: "forbidden" }), {
      status: 403,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const merchantRaw = row.merchant_raw as string | null | undefined;

  if (row.place_status === "user_locked") {
    const merchantNormalized = normalizeMerchant(merchantRaw);
    const { error: upErr } = await supabase
      .from("transactions")
      .update({
        merchant_normalized: merchantNormalized,
        pipeline_status: "enriched",
      })
      .eq("id", transactionId)
      .eq("user_id", user.id);

    if (upErr) {
      return new Response(JSON.stringify({ error: "server_misconfigured" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    await maybeWriteBackMerchantAliasFromCorrection(
      supabase,
      transactionId,
      user.id,
      "user_locked",
      {
        id: row.place_google_place_id as string | null | undefined,
        name: row.place_name as string | null,
        lat: row.place_lat as number | null,
        lng: row.place_lng as number | null,
      },
      row.share_location_lat as number | null | undefined,
      row.share_location_lng as number | null | undefined,
    );

    // MERCHANT INTELLIGENCE (shadow/on) for a user-locked place pick: same
    // fail-open, mode-gated reconciliation as the main Places-search path
    // further below, but against the transaction's already-persisted place
    // fields — there is no live Places call in this early-return branch,
    // since the user directly picked this place via the confirm-sheet
    // picker. See supabase/functions/_shared/merchant_resolution.ts and
    // supabase/migrations/20260724030000_merchant_intelligence_reconciliation.sql.
    const userLockedMiMode = getMerchantIntelligenceMode();
    const userLockedShareLat = row.share_location_lat as number | null | undefined;
    const userLockedShareLng = row.share_location_lng as number | null | undefined;
    const userLockedPlaceLat = row.place_lat as number | null | undefined;
    const userLockedPlaceLng = row.place_lng as number | null | undefined;
    const userLockedPlaceId = row.place_google_place_id as string | null | undefined;
    const userLockedPlaceName = row.place_name as string | null | undefined;

    if (
      userLockedMiMode !== "off" &&
      typeof userLockedShareLat === "number" &&
      typeof userLockedShareLng === "number" &&
      typeof userLockedPlaceLat === "number" &&
      typeof userLockedPlaceLng === "number" &&
      userLockedPlaceId &&
      userLockedPlaceName
    ) {
      try {
        // Best-effort, defensive parse purely to feed deriveBrandCandidates —
        // `row.llm_understanding` may be null, a stored `_error` record, or a
        // valid ReceiptUnderstanding-shaped object. Mirrors the same
        // defensive handling the PRECOMPUTED UNDERSTANDING section further
        // below in this function uses for the same column.
        const userLockedRawUnderstanding = row.llm_understanding as
          | Record<string, unknown>
          | null
          | undefined;
        const userLockedUnderstanding =
          userLockedRawUnderstanding &&
            typeof userLockedRawUnderstanding === "object" &&
            !("_error" in userLockedRawUnderstanding)
            ? parseReceiptUnderstanding(JSON.stringify(userLockedRawUnderstanding))
            : null;
        const userLockedBrandCandidates = userLockedUnderstanding
          ? deriveBrandCandidates(userLockedUnderstanding)
          : [];

        if (userLockedBrandCandidates.length > 0) {
          const userLockedGeohash = geohashEncode(
            userLockedShareLat,
            userLockedShareLng,
            ALIAS_GEOHASH_PRECISION,
          );
          const { data: userLockedCandidateRows, error: userLockedCandidatesError } =
            await supabase.rpc("lookup_merchant_candidates", {
              p_normalized_text: normalizeForCompare(userLockedBrandCandidates[0]),
              p_geohash: userLockedGeohash,
            });

          if (userLockedCandidatesError) {
            console.warn(
              `enrich-transaction[${transactionId}]: merchant-intelligence ` +
                `(${userLockedMiMode}, user_locked) candidate lookup failed — ` +
                `${userLockedCandidatesError.message}`,
            );
          } else {
            const userLockedMerchantCandidates: MerchantCandidateForScoring[] = (
              Array.isArray(userLockedCandidateRows) ? userLockedCandidateRows : []
            ).map((
              r: {
                merchant_id: string;
                canonical_name: string;
                typical_place_types: string[] | null;
              },
            ) => ({
              id: r.merchant_id,
              canonical_name: r.canonical_name,
              typical_place_types: r.typical_place_types,
            }));
            // No live Places call in this branch, so no `types` for the
            // "winner" — decideMerchantResolution treats a missing types
            // side as neutral (see typesAgree()).
            const userLockedDecision = decideMerchantResolution(
              userLockedBrandCandidates,
              { name: userLockedPlaceName, types: null },
              userLockedMerchantCandidates,
            );

            console.log(
              `enrich-transaction[${transactionId}]: merchant-intelligence ` +
                `${userLockedMiMode} (user_locked) — action=${userLockedDecision.action}, ` +
                `reason=${userLockedDecision.reason}, ` +
                `confidence=${userLockedDecision.confidence.toFixed(2)}, ` +
                `brandCandidate=${JSON.stringify(userLockedDecision.brandCandidate)}, ` +
                `placesWinner=${JSON.stringify(userLockedPlaceName)} (${userLockedPlaceId})`,
            );

            if (userLockedMiMode === "on") {
              // Fixed, high trust tier: this is a deliberate, multi-step
              // human pick, not an algorithmic guess — same 0.90 "user_locked"
              // correction trust tier as
              // 20260724010000_feedback_learning_hardening.sql's
              // upsert_merchant_alias_from_correction (v_base for
              // p_correction_type = 'user_locked'), not derived from
              // userLockedDecision.confidence.
              const { error: userLockedReconcileError } = await supabase.rpc(
                "reconcile_merchant_resolution",
                {
                  p_transaction_id: transactionId,
                  p_action: userLockedDecision.action,
                  p_google_place_id: userLockedPlaceId,
                  p_place_name: userLockedPlaceName,
                  p_lat: userLockedPlaceLat,
                  p_lng: userLockedPlaceLng,
                  p_geohash: userLockedGeohash,
                  p_resolution_method: "user_locked",
                  p_resolution_confidence: 0.9,
                  p_merchant_id: userLockedDecision.action === "attach_existing"
                    ? userLockedDecision.merchantId
                    : null,
                  p_canonical_name_for_new: userLockedDecision.action === "create_new"
                    ? userLockedDecision.canonicalNameForNew
                    : null,
                  p_normalized_name_key_for_new:
                    userLockedDecision.action === "create_new" &&
                      userLockedDecision.canonicalNameForNew
                      ? normalizeForCompare(userLockedDecision.canonicalNameForNew)
                      : null,
                  p_vendor_category: userLockedUnderstanding?.vendor_category ?? null,
                  p_typical_place_types: null,
                  p_location_confidence: 0.9,
                },
              );
              if (userLockedReconcileError) {
                console.warn(
                  `enrich-transaction[${transactionId}]: merchant-intelligence ` +
                    `(on, user_locked) reconcile failed — ` +
                    `${userLockedReconcileError.message}`,
                );
              }
            }
          }
        }
      } catch (e) {
        console.warn(
          `enrich-transaction[${transactionId}]: merchant-intelligence ` +
            `(${userLockedMiMode}, user_locked) reconciliation failed, ` +
            `continuing without it — ${String(e)}`,
        );
      }
    }

    return new Response(JSON.stringify({ ok: true, skipped_places: true }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // PRECOMPUTED UNDERSTANDING: as of the client-synchronous OCR+LLM pipeline
  // (see docs/decisions.md), the client already ran ocr-api's LLM
  // receipt-understanding step at capture time and synced the result as
  // transactions.llm_understanding. Prefer it — re-validated through the
  // same parseReceiptUnderstanding() used server-side, as a defense-in-depth
  // check against a version-skew or malformed sync — and only fall back to
  // calling ocr-api's POST /understand ourselves (the old flow) when it's
  // missing, is itself a stored failure record (`_error`), or fails to
  // re-validate. This keeps legacy app versions and transiently-failed
  // captures enrichable without a client redeploy.
  const precomputedRaw = row.llm_understanding as
    | Record<string, unknown>
    | null
    | undefined;
  let understanding: ReceiptUnderstanding | null = null;

  if (
    precomputedRaw && typeof precomputedRaw === "object" &&
    !("_error" in precomputedRaw)
  ) {
    understanding = parseReceiptUnderstanding(JSON.stringify(precomputedRaw));
  }

  if (understanding) {
    console.log(
      `enrich-transaction[${transactionId}]: using precomputed ` +
        `llm_understanding synced by the client — ` +
        `merchant=${JSON.stringify(understanding.merchant_name)}, ` +
        `category=${JSON.stringify(understanding.vendor_category)}`,
    );
  } else {
    // FALLBACK: no usable precomputed understanding — call ocr-api's LLM
    // step ourselves, exactly as before OCR+LLM became client-synchronous.
    // Full OCR body when the client kept it, falling back to the
    // always-synced header snippet for rows synced before the LLM-first
    // enrichment flow or web-originated captures.
    const rawOcrText = row.raw_ocr_text as string | null | undefined;
    const ocrHeaderText = row.ocr_header_text as string | null | undefined;
    const ocrText = (rawOcrText ?? ocrHeaderText ?? "").trim();

    if (ocrText.length === 0) {
      const { error: upErr } = await supabase
        .from("transactions")
        .update({
          merchant_normalized: normalizeMerchant(merchantRaw),
          pipeline_status: "failed_enrichment",
        })
        .eq("id", transactionId)
        .eq("user_id", user.id);

      if (upErr) {
        return new Response(JSON.stringify({ error: "server_misconfigured" }), {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      return new Response(
        JSON.stringify({ ok: false, reason: "no_ocr_text" }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // No heuristic fallback beyond this point during this testing phase —
    // a failed LLM call fails the whole enrichment.
    const ocrServiceUrl = Deno.env.get("OCR_SERVICE_URL");
    const ocrServiceSecret = Deno.env.get("OCR_SERVICE_SECRET");
    // Optional — only set in production, where ocr.receipt-drop.org is
    // gated by Cloudflare Access on top of X-OCR-Secret. See docs/decisions.md.
    const cfAccessClientId = Deno.env.get("CF_ACCESS_CLIENT_ID");
    const cfAccessClientSecret = Deno.env.get("CF_ACCESS_CLIENT_SECRET");

    if (!ocrServiceUrl || !ocrServiceSecret) {
      console.error(
        `enrich-transaction[${transactionId}]: OCR API not configured ` +
          `(OCR_SERVICE_URL/OCR_SERVICE_SECRET missing) — failing enrichment, no fallback`,
      );
      await supabase
        .from("transactions")
        .update({ pipeline_status: "failed_enrichment" })
        .eq("id", transactionId)
        .eq("user_id", user.id);

      return new Response(JSON.stringify({ error: "server_misconfigured" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    console.log(
      `enrich-transaction[${transactionId}]: no usable precomputed ` +
        `understanding — calling ocr-api /understand (fallback) — ` +
        `ocrTextChars=${ocrText.length}, ` +
        `source=${rawOcrText ? "raw_ocr_text" : "ocr_header_text"}`,
    );

    const llmResult = await callReceiptUnderstanding(
      { ocrServiceUrl, ocrServiceSecret, cfAccessClientId, cfAccessClientSecret },
      ocrText,
    );

    if (!llmResult.ok) {
      console.error(
        `enrich-transaction[${transactionId}]: LLM call failed after ` +
          `${llmResult.latencyMs}ms — error=${llmResult.error}` +
          (llmResult.raw ? `, raw=${JSON.stringify(llmResult.raw.slice(0, 300))}` : ""),
      );
      const { error: upErr } = await supabase
        .from("transactions")
        .update({
          pipeline_status: "failed_enrichment",
          merchant_normalized: normalizeMerchant(merchantRaw),
          llm_understanding: {
            _error: llmResult.error,
            _raw: llmResult.raw,
            _meta: { latency_ms: llmResult.latencyMs },
          },
        })
        .eq("id", transactionId)
        .eq("user_id", user.id);

      if (upErr) {
        return new Response(JSON.stringify({ error: "server_misconfigured" }), {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      return new Response(
        JSON.stringify({ ok: false, reason: "llm_error" }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    understanding = llmResult.understanding;

    console.log(
      `enrich-transaction[${transactionId}]: LLM understanding ok in ` +
        `${llmResult.latencyMs}ms (fallback call) — ` +
        `merchant=${JSON.stringify(understanding.merchant_name)} ` +
        `(confidence=${understanding.confidence.merchant}), ` +
        `category=${JSON.stringify(understanding.vendor_category)} ` +
        `(confidence=${understanding.confidence.category}), ` +
        `queries=${understanding.merchant_search_queries.length}, ` +
        `placeTypes=${understanding.google_place_types.length}`,
    );

    // Persist the LLM's structured output before touching Places, so it's
    // debuggable even if the function dies further down. Not needed on the
    // precomputed path above — the client already synced this field.
    const fallbackMerchantNormalized = understanding.merchant_name ??
      normalizeMerchant(merchantRaw);
    const { error: persistErr } = await supabase
      .from("transactions")
      .update({
        merchant_normalized: fallbackMerchantNormalized,
        llm_understanding: {
          ...understanding,
          _meta: {
            latency_ms: llmResult.latencyMs,
            prompt_source: rawOcrText ? "raw_ocr_text" : "ocr_header_text",
          },
        },
      })
      .eq("id", transactionId)
      .eq("user_id", user.id);

    if (persistErr) {
      return new Response(JSON.stringify({ error: "server_misconfigured" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
  }

  const merchantNormalized = understanding.merchant_name ??
    normalizeMerchant(merchantRaw);

  // Payment receipts (Touch 'n Go, Maybank, GrabPay, etc.) are not physical
  // venues — a Google Places search would waste API quota and produce wrong
  // pins. Mark enriched and skip the Places step entirely.
  if (understanding.receipt_type === "payment") {
    const { error: upErr } = await supabase
      .from("transactions")
      .update({
        merchant_normalized: merchantNormalized,
        pipeline_status: "enriched",
      })
      .eq("id", transactionId)
      .eq("user_id", user.id);

    if (upErr) {
      return new Response(JSON.stringify({ error: "server_misconfigured" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    console.log(
      `enrich-transaction[${transactionId}]: skipped Places (receipt_type=payment)`,
    );
    return new Response(
      JSON.stringify({ ok: true, skipped_places: true, reason: "payment_receipt" }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const shareLat = row.share_location_lat;
  const shareLng = row.share_location_lng;
  const hasLocation =
    typeof shareLat === "number" && typeof shareLng === "number";
  // Usable text requires both a long-enough string AND that the LLM itself
  // trusted its own extraction — tightens the length-only gate without
  // discarding the already-tuned scoring weights/caps below.
  const hasUsableText = understanding.merchant_name != null &&
    isUsableMerchantText(understanding.merchant_name) &&
    understanding.confidence.merchant >= 0.6;
  const receiptLocationSignal = hasReceiptLocationSignal(understanding);

  // ALIAS FAST-PATH: skip Google Places entirely if this exact LLM-canonical
  // merchant name near this exact location has already been resolved
  // before. Keyed on the LLM's corrected name (not the raw OCR guess) so
  // OCR variants of the same merchant collapse onto one cache key.
  // Skip when the receipt carries its own address/clue — share geohash would
  // point at upload location, not the store on the receipt.
  if (hasLocation && hasUsableText && !receiptLocationSignal) {
    const aliasKey = normalizeForCompare(understanding.merchant_name!);
    const geohash = geohashEncode(shareLat, shareLng, ALIAS_GEOHASH_PRECISION);
    try {
      const { data: aliasRows } = await supabase.rpc(
        "lookup_merchant_alias",
        { p_alias_text: aliasKey, p_geohash: geohash },
      );
      const alias = Array.isArray(aliasRows) ? aliasRows[0] : null;
      // A hit below ALIAS_MIN_TRUST_CONFIDENCE has decayed too far to trust
      // as authoritative — fall through to the normal Places flow exactly as
      // if there had been no alias hit at all (see place_matching.ts).
      if (alias && alias.confidence >= ALIAS_MIN_TRUST_CONFIDENCE) {
        const { error: aliasUpErr } = await supabase
          .from("transactions")
          .update({
            place_google_place_id: alias.place_id,
            place_name: alias.name,
            place_lat: alias.lat,
            place_lng: alias.lng,
            place_confidence: Math.min(0.97, alias.confidence),
            place_status: "guess",
            pipeline_status: "enriched",
          })
          .eq("id", transactionId)
          .eq("user_id", user.id);
        if (!aliasUpErr) {
          console.log(
            `enrich-transaction[${transactionId}]: resolved via alias cache ` +
              `(key=${JSON.stringify(aliasKey)}) — skipped Places, place=` +
              `${JSON.stringify(alias.name)}`,
          );
          return new Response(
            JSON.stringify({ ok: true, resolved_via: "alias" }),
            {
              status: 200,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            },
          );
        }
        // Update failed — fall through to the normal Places flow below.
      }
    } catch {
      // Alias lookup is a fast-path optimization, not required for
      // correctness — fall through to the normal Places flow on any failure.
    }
  }

  const apiKey = Deno.env.get("GOOGLE_PLACES_API_KEY");
  if (!apiKey) {
    await supabase
      .from("transactions")
      .update({ pipeline_status: "failed_enrichment" })
      .eq("id", transactionId)
      .eq("user_id", user.id);

    return new Response(JSON.stringify({ error: "server_misconfigured" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const includedTypes = resolveIncludedTypes(understanding);
  const textQueries = buildLlmTextQueries(understanding);

  if (textQueries.length === 0 && !hasLocation) {
    // No merchant text, no address-derived query, and no GPS to anchor a
    // nearby search — nothing for Places to search against.
    console.warn(
      `enrich-transaction[${transactionId}]: no search signal — LLM produced ` +
        `no usable queries (merchant=${JSON.stringify(understanding.merchant_name)}, ` +
        `address=${JSON.stringify(understanding.address_text)}) and no share GPS`,
    );
    const updated = await markPlacesFailure(
      supabase,
      transactionId,
      user.id,
      merchantNormalized,
    );
    if (updated) {
      return new Response(
        JSON.stringify({ ok: false, reason: "no_search_signal" }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }
    return new Response(JSON.stringify({ error: "server_misconfigured" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  type GooglePlace = {
    id?: string;
    displayName?: { text?: string } | string;
    location?: { latitude?: number; longitude?: number };
    types?: string[];
  };

  type PlaceCandidate = {
    id: string;
    name: string | null;
    lat: number | null;
    lng: number | null;
    types: string[] | null;
  };

  const placesFieldMask =
    "places.id,places.displayName,places.formattedAddress,places.location,places.types";

  async function fetchTextSearch(query: string): Promise<GooglePlace[] | null> {
    const body: Record<string, unknown> = {
      textQuery: query,
      languageCode: "ms",
      regionCode: "MY",
      maxResultCount: 8,
    };
    if (hasLocation && !receiptLocationSignal) {
      body.locationBias = {
        circle: {
          center: { latitude: shareLat, longitude: shareLng },
          radius: SEARCH_RADIUS_METERS,
        },
      };
    }
    try {
      const resp = await fetchFn(
        "https://places.googleapis.com/v1/places:searchText",
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-Goog-Api-Key": apiKey,
            "X-Goog-FieldMask": placesFieldMask,
          },
          body: JSON.stringify(body),
        },
      );
      if (!resp.ok) return null;
      const json = (await resp.json()) as { places?: GooglePlace[] };
      return json.places ?? [];
    } catch {
      return null;
    }
  }

  async function fetchNearbySearch(): Promise<GooglePlace[] | null> {
    if (!hasLocation || receiptLocationSignal) return null;
    try {
      const resp = await fetchFn(
        "https://places.googleapis.com/v1/places:searchNearby",
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-Goog-Api-Key": apiKey,
            "X-Goog-FieldMask": placesFieldMask,
          },
          body: JSON.stringify({
            includedTypes,
            maxResultCount: 10,
            languageCode: "ms",
            regionCode: "MY",
            rankPreference: "DISTANCE",
            locationRestriction: {
              circle: {
                center: { latitude: shareLat, longitude: shareLng },
                radius: SEARCH_RADIUS_METERS,
              },
            },
          }),
        },
      );
      if (!resp.ok) return null;
      const json = (await resp.json()) as { places?: GooglePlace[] };
      return json.places ?? [];
    } catch {
      return null;
    }
  }

  // Up to 3 distinct queries built from the LLM's merchant/location
  // understanding get their own Text Search call, run concurrently with a
  // single Nearby Search using the LLM's place types.
  const [textResults, nearbyResult] = await Promise.all([
    Promise.all(textQueries.map((q) => fetchTextSearch(q))),
    fetchNearbySearch(),
  ]);

  if (textResults.every((r) => r === null) && nearbyResult === null) {
    console.warn(
      `enrich-transaction[${transactionId}]: all Places calls failed — ` +
        `queries=${JSON.stringify(textQueries)}, includedTypes=${JSON.stringify(includedTypes)}`,
    );
    const updated = await markPlacesFailure(
      supabase,
      transactionId,
      user.id,
      merchantNormalized,
    );
    if (updated) {
      return new Response(
        JSON.stringify({ ok: false, reason: "places_error" }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }
    return new Response(JSON.stringify({ error: "server_misconfigured" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  function toCandidates(places: GooglePlace[]): PlaceCandidate[] {
    return places
      .filter((p): p is GooglePlace & { id: string } => typeof p.id === "string")
      .map((p) => ({
        id: stripPlacesResourcePrefix(p.id),
        name: placeDisplayName(p),
        lat: p.location?.latitude ?? null,
        lng: p.location?.longitude ?? null,
        types: Array.isArray(p.types) ? p.types : null,
      }));
  }

  const candidatesById = new Map<string, PlaceCandidate>();
  for (const c of [
    ...textResults.flatMap((r) => toCandidates(r ?? [])),
    ...toCandidates(nearbyResult ?? []),
  ]) {
    const existing = candidatesById.get(c.id);
    if (!existing || (existing.lat == null && c.lat != null)) {
      candidatesById.set(c.id, c);
    }
  }

  if (candidatesById.size === 0) {
    console.warn(
      `enrich-transaction[${transactionId}]: Places returned zero candidates ` +
        `— queries=${JSON.stringify(textQueries)}, includedTypes=${JSON.stringify(includedTypes)}, ` +
        `hasLocation=${hasLocation}`,
    );
    const { error: upErr } = await supabase
      .from("transactions")
      .update({
        pipeline_status: "failed_enrichment",
        merchant_normalized: merchantNormalized,
      })
      .eq("id", transactionId)
      .eq("user_id", user.id);

    if (upErr) {
      return new Response(JSON.stringify({ error: "server_misconfigured" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(
      JSON.stringify({ ok: false, reason: "no_places" }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  // Weights/cap shift by how much each signal can be trusted: usable LLM
  // merchant text pulls toward a text+location-confirmed match (cap 0.97);
  // low-confidence/garbled text leans almost entirely on Nearby Search's
  // distance ranking instead, capped lower (0.65) so it reads as a guess.
  // Receipt address/clue present: text-only scoring — no distance from
  // upload GPS (the user may have scanned the receipt elsewhere).
  const weights = receiptLocationSignal
    ? { textWeight: 1, distWeight: 0, cap: 0.97 }
    : {
      textWeight: hasUsableText ? 0.6 : 0.15,
      distWeight: hasUsableText ? 0.4 : 0.85,
      cap: !hasLocation ? 0.9 : hasUsableText ? 0.97 : 0.65,
    };
  const location = hasLocation && !receiptLocationSignal
    ? { lat: shareLat, lng: shareLng }
    : null;

  let winner: PlaceCandidate | null = null;
  let winnerConfidence = -1;

  for (const c of candidatesById.values()) {
    // Scored against the best match across every queried text, then
    // penalized if the candidate's own Places types share nothing with the
    // LLM's expected vendor category (keeps a same-block Nike Store from
    // outscoring a lower-text-match food candidate on a food receipt).
    const baseScore = scoreCandidate(c, textQueries, weights, location);
    const confidence = adjustScoreForTypeMatch(
      baseScore,
      c.types,
      understanding.google_place_types,
    );
    if (confidence > winnerConfidence) {
      winnerConfidence = confidence;
      winner = c;
    }
  }

  if (!winner) {
    return new Response(JSON.stringify({ error: "server_misconfigured" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  console.log(
    `enrich-transaction[${transactionId}]: resolved via Places — ` +
      `place=${JSON.stringify(winner.name)}, confidence=${winnerConfidence.toFixed(2)}, ` +
      `hasUsableText=${hasUsableText}`,
  );

  const { error: upErr } = await supabase
    .from("transactions")
    .update({
      merchant_normalized: merchantNormalized,
      place_google_place_id: winner.id,
      place_name: winner.name,
      place_lat: winner.lat,
      place_lng: winner.lng,
      place_confidence: Math.round(winnerConfidence * 100) / 100,
      place_status: "guess",
      pipeline_status: "enriched",
    })
    .eq("id", transactionId)
    .eq("user_id", user.id);

  if (upErr) {
    return new Response(JSON.stringify({ error: "server_misconfigured" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // MERCHANT INTELLIGENCE (shadow/on): fail-open, mode-gated brand/location
  // reconciliation against the global merchants/merchant_locations catalog —
  // separate from (and never affecting) the alias cache below. No-ops
  // entirely in "off" mode (the default) — zero extra RPC calls, latency, or
  // logging. See supabase/functions/_shared/merchant_resolution.ts and
  // supabase/migrations/20260724030000_merchant_intelligence_reconciliation.sql.
  const merchantIntelligenceMode = getMerchantIntelligenceMode();
  if (
    merchantIntelligenceMode !== "off" &&
    hasLocation &&
    winner.lat != null &&
    winner.lng != null &&
    winner.name
  ) {
    try {
      const brandCandidates = deriveBrandCandidates(understanding);
      if (brandCandidates.length > 0) {
        // Deliberately the SAME geohash formula/inputs as the alias
        // fast-path above (geohashEncode(shareLat, shareLng, ...)), not one
        // derived from the Places winner's own coordinates — this keeps the
        // bucketing scheme aligned with merchant_aliases, so
        // lookup_merchant_candidates' alias-evidence signal actually lines
        // up with existing alias rows for this same location.
        const miGeohash = geohashEncode(shareLat, shareLng, ALIAS_GEOHASH_PRECISION);
        const { data: candidateRows, error: candidatesError } = await supabase
          .rpc("lookup_merchant_candidates", {
            p_normalized_text: normalizeForCompare(brandCandidates[0]),
            p_geohash: miGeohash,
          });

        if (candidatesError) {
          console.warn(
            `enrich-transaction[${transactionId}]: merchant-intelligence ` +
              `(${merchantIntelligenceMode}) candidate lookup failed — ` +
              `${candidatesError.message}`,
          );
        } else {
          const merchantCandidates: MerchantCandidateForScoring[] = (
            Array.isArray(candidateRows) ? candidateRows : []
          ).map((
            r: {
              merchant_id: string;
              canonical_name: string;
              typical_place_types: string[] | null;
            },
          ) => ({
            id: r.merchant_id,
            canonical_name: r.canonical_name,
            typical_place_types: r.typical_place_types,
          }));
          const decision = decideMerchantResolution(
            brandCandidates,
            { name: winner.name, types: winner.types },
            merchantCandidates,
          );
          // The transaction's own already-computed Places-match confidence
          // (same value written to place_confidence above) — not
          // decision.confidence, which only measures brand-vs-Places
          // internal agreement and is still fine to log for visibility.
          const roundedWinnerConfidence = Math.round(winnerConfidence * 100) / 100;

          console.log(
            `enrich-transaction[${transactionId}]: merchant-intelligence ` +
              `${merchantIntelligenceMode} — action=${decision.action}, ` +
              `reason=${decision.reason}, confidence=${decision.confidence.toFixed(2)}, ` +
              `brandCandidate=${JSON.stringify(decision.brandCandidate)}, ` +
              `placesWinner=${JSON.stringify(winner.name)} (${winner.id})`,
          );

          if (merchantIntelligenceMode === "on") {
            const { error: reconcileError } = await supabase.rpc(
              "reconcile_merchant_resolution",
              {
                p_transaction_id: transactionId,
                p_action: decision.action,
                p_google_place_id: winner.id,
                p_place_name: winner.name,
                p_lat: winner.lat,
                p_lng: winner.lng,
                p_geohash: miGeohash,
                p_resolution_method: decision.action === "attach_existing"
                  ? "fuzzy_brand"
                  : "places_search",
                p_resolution_confidence: roundedWinnerConfidence,
                p_merchant_id: decision.action === "attach_existing"
                  ? decision.merchantId
                  : null,
                p_canonical_name_for_new: decision.action === "create_new"
                  ? decision.canonicalNameForNew
                  : null,
                p_normalized_name_key_for_new:
                  decision.action === "create_new" && decision.canonicalNameForNew
                    ? normalizeForCompare(decision.canonicalNameForNew)
                    : null,
                p_vendor_category: understanding.vendor_category,
                p_typical_place_types: winner.types,
                p_location_confidence: roundedWinnerConfidence,
              },
            );
            if (reconcileError) {
              console.warn(
                `enrich-transaction[${transactionId}]: merchant-intelligence ` +
                  `(on) reconcile failed — ${reconcileError.message}`,
              );
            }
          }
        }
      }
    } catch (e) {
      console.warn(
        `enrich-transaction[${transactionId}]: merchant-intelligence ` +
          `(${merchantIntelligenceMode}) reconciliation failed, continuing ` +
          `without it — ${String(e)}`,
      );
    }
  }

  // Remember this resolution for future scans of the same merchant near the
  // same location, so they can skip Places entirely (see the alias
  // fast-path above). Best-effort — a failed write here doesn't affect this
  // transaction's own (already-saved) enrichment result.
  if (
    hasUsableText &&
    winnerConfidence >= ALIAS_SAVE_CONFIDENCE_THRESHOLD &&
    winner.lat != null &&
    winner.lng != null &&
    (hasLocation || receiptLocationSignal)
  ) {
    const aliasLat = receiptLocationSignal ? winner.lat! : shareLat;
    const aliasLng = receiptLocationSignal ? winner.lng! : shareLng;
    try {
      await supabase.rpc("upsert_merchant_alias", {
        p_alias_text: normalizeForCompare(understanding.merchant_name!),
        p_geohash: geohashEncode(aliasLat, aliasLng, ALIAS_GEOHASH_PRECISION),
        p_place_id: winner.id,
        p_name: winner.name,
        p_lat: winner.lat,
        p_lng: winner.lng,
        p_confidence: winnerConfidence,
      });
    } catch {
      // Non-fatal — see comment above.
    }
  }

  // Free-text merchant-name correction write-back: reuses this request's
  // already-resolved Places winner (no extra Places call) — the
  // corroboration-gate tiering that makes this safe against a bad edit
  // lives in upsert_merchant_alias_from_correction() itself, so this fires
  // regardless of winnerConfidence.
  await maybeWriteBackMerchantAliasFromCorrection(
    supabase,
    transactionId,
    user.id,
    "free_text",
    { id: winner.id, name: winner.name, lat: winner.lat, lng: winner.lng },
    hasLocation ? shareLat : null,
    hasLocation ? shareLng : null,
  );

  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// Only bind a real port when this file is run as the entry script (the
// actual Supabase Edge Runtime always invokes index.ts directly, so
// `import.meta.main` is true there) — not when a test file imports
// `handleEnrichTransactionRequest` from it.
if (import.meta.main) {
  Deno.serve((req) => handleEnrichTransactionRequest(req));
}
