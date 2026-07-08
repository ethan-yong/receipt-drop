import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  ALIAS_GEOHASH_PRECISION,
  ALIAS_SAVE_CONFIDENCE_THRESHOLD,
  CATEGORY_TO_PLACE_TYPES,
  DEFAULT_NEARBY_TYPES,
  MerchantCandidateInput,
  SEARCH_RADIUS_METERS,
  buildTextSearchQueries,
  geohashEncode,
  isUsableMerchantText,
  normalizeForCompare,
  scoreCandidate,
} from "../_shared/place_matching.ts";

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
  merchantRaw: string | null | undefined,
): Promise<boolean> {
  const { error } = await client
    .from("transactions")
    .update({
      pipeline_status: "failed_enrichment",
      merchant_normalized: normalizeMerchant(merchantRaw),
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

  const searchText = (
    (row.merchant_normalized as string | null | undefined) ??
    merchantRaw ??
    ""
  ).trim();

  if (searchText.length === 0) {
    const { error: upErr } = await supabase
      .from("transactions")
      .update({
        merchant_normalized: null,
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
      JSON.stringify({ ok: false, reason: "no_merchant_text" }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  // Ranked merchant guesses from lib/domain/logic/merchant_extractor.dart,
  // synced onto the row alongside merchant_raw/merchant_normalized. Rows
  // synced before this column existed (or a web-originated row with no
  // candidates) fall back to searchText alone via buildTextSearchQueries.
  const merchantCandidates =
    (row.merchant_candidates as MerchantCandidateInput[] | null) ?? null;
  // Extra top-of-receipt OCR context, always populated (unlike raw_ocr_text,
  // which is review-only). Not used in matching yet — read here so it's
  // available for a future scoring refinement without another migration.
  const _ocrHeaderText = row.ocr_header_text as string | null | undefined;

  const shareLat = row.share_location_lat;
  const shareLng = row.share_location_lng;
  const hasLocation =
    typeof shareLat === "number" && typeof shareLng === "number";
  const topCandidateConfidence = merchantCandidates?.[0]?.confidence;
  // Usable text requires both a long-enough string AND, when we have a
  // candidate-level confidence signal, that the extractor itself trusted its
  // top guess — tightens the existing length-only gate without discarding
  // its already-tuned weights/caps below.
  const hasUsableText = isUsableMerchantText(searchText) &&
    (topCandidateConfidence === undefined || topCandidateConfidence >= 0.6);

  // ALIAS FAST-PATH: skip Google Places entirely if this exact merchant text
  // near this exact location has already been resolved before.
  if (hasLocation && hasUsableText) {
    const topCandidateText = merchantCandidates?.[0]?.text ?? searchText;
    const aliasKey = normalizeForCompare(topCandidateText);
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
            merchant_normalized: normalizeMerchant(merchantRaw),
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

  const categoryGuess = row.category_guess as string | null | undefined;
  const categoryConfidence =
    (row.category_confidence as number | null | undefined) ?? 0;
  const includedTypes =
    categoryGuess && categoryConfidence >= 0.5 && CATEGORY_TO_PLACE_TYPES[categoryGuess]
      ? CATEGORY_TO_PLACE_TYPES[categoryGuess]
      : DEFAULT_NEARBY_TYPES;

  type GooglePlace = {
    id?: string;
    displayName?: { text?: string } | string;
    location?: { latitude?: number; longitude?: number };
  };

  type PlaceCandidate = {
    id: string;
    name: string | null;
    lat: number | null;
    lng: number | null;
  };

  const placesFieldMask =
    "places.id,places.displayName,places.formattedAddress,places.location";

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

  // Up to 2 distinct ranked candidates get their own Text Search query
  // (falls back to the single searchText query when merchant_candidates is
  // absent — e.g. rows synced before this column existed).
  const textQueries = buildTextSearchQueries(merchantCandidates, searchText);

  const [textResults, nearbyResult] = await Promise.all([
    Promise.all(textQueries.map((q) => fetchTextSearch(q))),
    fetchNearbySearch(),
  ]);

  if (textResults.every((r) => r === null) && nearbyResult === null) {
    const updated = await markPlacesFailure(
      supabase,
      transactionId,
      user.id,
      merchantRaw,
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
    const { error: upErr } = await supabase
      .from("transactions")
      .update({
        pipeline_status: "failed_enrichment",
        merchant_normalized: normalizeMerchant(merchantRaw),
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

  // Weights/cap shift by how much each signal can be trusted: usable OCR
  // text pulls toward a text+location-confirmed match (cap 0.97); garbled
  // text (e.g. "Mel") leans almost entirely on Nearby Search's distance
  // ranking instead, capped lower (0.65) so it reads as a guess, not a
  // confirmed match.
  const weights = {
    textWeight: hasUsableText ? 0.6 : 0.15,
    distWeight: hasUsableText ? 0.4 : 0.85,
    cap: !hasLocation ? 0.9 : hasUsableText ? 0.97 : 0.65,
  };
  const location = hasLocation ? { lat: shareLat, lng: shareLng } : null;

  let winner: PlaceCandidate | null = null;
  let winnerConfidence = -1;

  for (const c of candidatesById.values()) {
    // Scored against the best match across every queried text (not just the
    // single top candidate), so a Places result matching a shorter/cleaner
    // alternate candidate isn't penalized for not matching the noisiest one.
    const confidence = scoreCandidate(c, textQueries, weights, location);
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

  const { error: upErr } = await supabase
    .from("transactions")
    .update({
      merchant_normalized: normalizeMerchant(merchantRaw),
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
      const topCandidateText = merchantCandidates?.[0]?.text ?? searchText;
      await supabase.rpc("upsert_merchant_alias", {
        p_alias_text: normalizeForCompare(topCandidateText),
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
