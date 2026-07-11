import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  ALIAS_GEOHASH_PRECISION,
  ALIAS_SAVE_CONFIDENCE_THRESHOLD,
  SEARCH_RADIUS_METERS,
  geohashEncode,
  isUsableMerchantText,
  normalizeForCompare,
  scoreCandidate,
} from "../_shared/place_matching.ts";
import {
  adjustScoreForTypeMatch,
  buildLlmTextQueries,
  callReceiptUnderstanding,
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

Deno.serve(async (req) => {
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
      { ocrServiceUrl, ocrServiceSecret },
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

  // ALIAS FAST-PATH: skip Google Places entirely if this exact LLM-canonical
  // merchant name near this exact location has already been resolved
  // before. Keyed on the LLM's corrected name (not the raw OCR guess) so
  // OCR variants of the same merchant collapse onto one cache key.
  if (hasLocation && hasUsableText) {
    const aliasKey = normalizeForCompare(understanding.merchant_name!);
    const geohash = geohashEncode(shareLat, shareLng, ALIAS_GEOHASH_PRECISION);
    try {
      const { data: aliasRows } = await supabase.rpc(
        "lookup_merchant_alias",
        { p_alias_text: aliasKey, p_geohash: geohash },
      );
      const alias = Array.isArray(aliasRows) ? aliasRows[0] : null;
      if (alias) {
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
    if (hasLocation) {
      body.locationBias = {
        circle: {
          center: { latitude: shareLat, longitude: shareLng },
          radius: SEARCH_RADIUS_METERS,
        },
      };
    }
    try {
      const resp = await fetch(
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
    if (!hasLocation) return null;
    try {
      const resp = await fetch(
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
  const weights = {
    textWeight: hasUsableText ? 0.6 : 0.15,
    distWeight: hasUsableText ? 0.4 : 0.85,
    cap: !hasLocation ? 0.9 : hasUsableText ? 0.97 : 0.65,
  };
  const location = hasLocation ? { lat: shareLat, lng: shareLng } : null;

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

  // Remember this resolution for future scans of the same merchant near the
  // same location, so they can skip Places entirely (see the alias
  // fast-path above). Best-effort — a failed write here doesn't affect this
  // transaction's own (already-saved) enrichment result.
  if (
    hasLocation &&
    hasUsableText &&
    winnerConfidence >= ALIAS_SAVE_CONFIDENCE_THRESHOLD
  ) {
    try {
      await supabase.rpc("upsert_merchant_alias", {
        p_alias_text: normalizeForCompare(understanding.merchant_name!),
        p_geohash: geohashEncode(shareLat, shareLng, ALIAS_GEOHASH_PRECISION),
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

  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});
