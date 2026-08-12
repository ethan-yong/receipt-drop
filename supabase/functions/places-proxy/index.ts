import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  CATEGORY_TO_PLACE_TYPES,
  DEFAULT_NEARBY_TYPES,
  MerchantCandidateInput,
  SEARCH_RADIUS_METERS,
  buildTextSearchQueries,
  haversineMeters,
  isUsableMerchantText,
  scoreCandidate,
} from "../_shared/place_matching.ts";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type RawGooglePlace = {
  id?: string;
  displayName?: { text?: string } | string;
  formattedAddress?: string;
  location?: { latitude?: number; longitude?: number };
};

function stripPlacesPrefix(id: string): string {
  return id.replace(/^places\//, "");
}

// Google Places photos for a venue, cached in `place_photos_cache` +
// re-hosted in the `place-photos` Storage bucket so repeat sheet-opens for
// the same place (by any user) never re-hit Google's billed Photo Media
// endpoint. See 20260811180001_place_photos_cache.sql.
const PLACE_PHOTO_LIMIT = 3;
const PLACE_PHOTO_CACHE_TTL_MS = 30 * 24 * 60 * 60 * 1000; // 30 days

async function handlePlacePhotosMode(
  body: Record<string, unknown>,
  apiKey: string,
  supabaseUrl: string,
  serviceRoleKey: string,
): Promise<Response> {
  const placeId = body["placeId"];
  if (typeof placeId !== "string" || placeId.trim().length === 0) {
    return new Response(JSON.stringify({ error: "bad_request" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // Service-role client: place_photos_cache has zero client policies (global,
  // not per-user) and only this Edge Function ever writes to the
  // place-photos bucket.
  const admin = createClient(supabaseUrl, serviceRoleKey);

  const { data: cached } = await admin
    .from("place_photos_cache")
    .select("photo_urls, fetched_at")
    .eq("google_place_id", placeId)
    .maybeSingle();

  const cachedUrls = (cached?.photo_urls as string[] | undefined) ?? [];
  if (
    cached &&
    Date.now() - new Date(cached.fetched_at as string).getTime() <
      PLACE_PHOTO_CACHE_TTL_MS
  ) {
    return new Response(JSON.stringify({ photoUrls: cachedUrls }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // Any failure below falls back to whatever's cached (possibly stale, or
  // empty on a first-ever fetch) rather than surfacing an error — a photo
  // carousel with fewer/no place photos degrades gracefully in the UI.
  try {
    const detailsResp = await fetch(
      `https://places.googleapis.com/v1/places/${placeId}?fields=photos`,
      { headers: { "X-Goog-Api-Key": apiKey } },
    );
    if (!detailsResp.ok) {
      console.error(
        `places-proxy place details failed: ${detailsResp.status} ${await detailsResp.text()}`,
      );
      return new Response(JSON.stringify({ photoUrls: cachedUrls }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const detailsJson = (await detailsResp.json()) as {
      photos?: { name?: string }[];
    };
    const photoNames = (detailsJson.photos ?? [])
      .map((p) => p.name)
      .filter((n): n is string => typeof n === "string")
      .slice(0, PLACE_PHOTO_LIMIT);

    const photoUrls: string[] = [];
    for (let i = 0; i < photoNames.length; i++) {
      const mediaResp = await fetch(
        `https://places.googleapis.com/v1/${photoNames[i]}/media?maxWidthPx=800&skipHttpRedirect=true`,
        { headers: { "X-Goog-Api-Key": apiKey } },
      );
      if (!mediaResp.ok) continue;
      const mediaJson = (await mediaResp.json()) as { photoUri?: string };
      if (!mediaJson.photoUri) continue;

      const imgResp = await fetch(mediaJson.photoUri);
      if (!imgResp.ok) continue;
      const bytes = new Uint8Array(await imgResp.arrayBuffer());
      const storagePath = `${placeId}/${i}.jpg`;
      const { error: uploadError } = await admin.storage
        .from("place-photos")
        .upload(storagePath, bytes, {
          contentType: imgResp.headers.get("content-type") ?? "image/jpeg",
          upsert: true,
        });
      if (uploadError) {
        console.error(`places-proxy photo upload failed: ${uploadError.message}`);
        continue;
      }
      const { data: pub } = admin.storage
        .from("place-photos")
        .getPublicUrl(storagePath);
      photoUrls.push(pub.publicUrl);
    }

    if (photoUrls.length > 0) {
      await admin.from("place_photos_cache").upsert({
        google_place_id: placeId,
        photo_urls: photoUrls,
        fetched_at: new Date().toISOString(),
      });
    }

    return new Response(
      JSON.stringify({
        photoUrls: photoUrls.length > 0 ? photoUrls : cachedUrls,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error(`places-proxy place_photos threw: ${err}`);
    return new Response(JSON.stringify({ photoUrls: cachedUrls }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
}

function placeDisplayName(p: RawGooglePlace): string | null {
  const d = p.displayName;
  if (d == null) return null;
  if (typeof d === "string") return d;
  return d.text ?? null;
}

async function handleNearbyMode(
  body: Record<string, unknown>,
  apiKey: string,
): Promise<Response> {
  const lat = body["lat"];
  const lng = body["lng"];
  if (typeof lat !== "number" || typeof lng !== "number") {
    return new Response(JSON.stringify({ error: "bad_request" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const candidatesRaw = body["candidates"];
  const candidates: MerchantCandidateInput[] | null = Array.isArray(
      candidatesRaw,
    )
    ? (candidatesRaw as MerchantCandidateInput[])
    : null;

  const queryText = typeof body["query"] === "string"
    ? (body["query"] as string)
    : "";
  const categoryGuess = typeof body["category"] === "string"
    ? (body["category"] as string)
    : null;
  const limitRaw = body["limit"];
  const limit = typeof limitRaw === "number"
    ? Math.min(Math.max(1, limitRaw), 10)
    : 5;

  const fieldMask =
    "places.id,places.displayName,places.formattedAddress,places.location";

  const textQueries = buildTextSearchQueries(candidates, queryText, 2).filter(
    (q) => q.length > 0,
  );

  async function fetchText(query: string): Promise<RawGooglePlace[] | null> {
    try {
      const resp = await fetch(
        "https://places.googleapis.com/v1/places:searchText",
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-Goog-Api-Key": apiKey,
            "X-Goog-FieldMask": fieldMask,
          },
          body: JSON.stringify({
            textQuery: query,
            languageCode: "ms",
            regionCode: "MY",
            maxResultCount: 8,
            locationBias: {
              circle: {
                center: { latitude: lat, longitude: lng },
                radius: SEARCH_RADIUS_METERS,
              },
            },
          }),
        },
      );
      if (!resp.ok) {
        console.error(
          `places-proxy searchText failed: ${resp.status} ${await resp.text()}`,
        );
        return null;
      }
      const json = (await resp.json()) as { places?: RawGooglePlace[] };
      return json.places ?? [];
    } catch (err) {
      console.error(`places-proxy searchText threw: ${err}`);
      return null;
    }
  }

  async function fetchNearby(): Promise<RawGooglePlace[] | null> {
    const includedTypes = categoryGuess &&
        CATEGORY_TO_PLACE_TYPES[categoryGuess]
      ? CATEGORY_TO_PLACE_TYPES[categoryGuess]
      : DEFAULT_NEARBY_TYPES;
    try {
      const resp = await fetch(
        "https://places.googleapis.com/v1/places:searchNearby",
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-Goog-Api-Key": apiKey,
            "X-Goog-FieldMask": fieldMask,
          },
          body: JSON.stringify({
            includedTypes,
            maxResultCount: 10,
            languageCode: "ms",
            regionCode: "MY",
            rankPreference: "DISTANCE",
            locationRestriction: {
              circle: {
                center: { latitude: lat, longitude: lng },
                radius: SEARCH_RADIUS_METERS,
              },
            },
          }),
        },
      );
      if (!resp.ok) {
        console.error(
          `places-proxy searchNearby failed: ${resp.status} ${await resp.text()}`,
        );
        return null;
      }
      const json = (await resp.json()) as { places?: RawGooglePlace[] };
      return json.places ?? [];
    } catch (err) {
      console.error(`places-proxy searchNearby threw: ${err}`);
      return null;
    }
  }

  const [textResultGroups, nearbyResults] = await Promise.all([
    textQueries.length > 0
      ? Promise.all(textQueries.map((q) => fetchText(q)))
      : Promise.resolve([]),
    fetchNearby(),
  ]);

  type ScoredPlace = {
    id: string;
    name: string | null;
    address: string;
    lat: number | null;
    lng: number | null;
  };

  const byId = new Map<string, ScoredPlace>();
  for (
    const p of [
      ...textResultGroups.flatMap((r) => r ?? []),
      ...(nearbyResults ?? []),
    ]
  ) {
    if (typeof p.id !== "string") continue;
    const id = stripPlacesPrefix(p.id);
    const existing = byId.get(id);
    const candidate: ScoredPlace = {
      id,
      name: placeDisplayName(p),
      address: p.formattedAddress ?? "",
      lat: p.location?.latitude ?? null,
      lng: p.location?.longitude ?? null,
    };
    if (!existing || (existing.lat == null && candidate.lat != null)) {
      byId.set(id, candidate);
    }
  }

  const hasUsableText = isUsableMerchantText(queryText) ||
    (candidates != null && candidates.some((c) => isUsableMerchantText(c.text)));

  const weights = {
    textWeight: hasUsableText ? 0.6 : 0.15,
    distWeight: hasUsableText ? 0.4 : 0.85,
    cap: hasUsableText ? 0.97 : 0.65,
  };
  const location = { lat, lng };
  const allQueryTexts = textQueries.length > 0 ? textQueries : [queryText];

  const ranked = Array.from(byId.values())
    .map((c) => ({
      ...c,
      confidence: scoreCandidate(c, allQueryTexts, weights, location),
      distanceMeters: c.lat != null && c.lng != null
        ? haversineMeters(lat, lng, c.lat, c.lng)
        : null,
    }))
    .filter((c) => c.lat != null && c.lng != null)
    .sort((a, b) => b.confidence - a.confidence)
    .slice(0, limit)
    .map((c) => ({
      id: c.id,
      name: c.name ?? "",
      address: c.address,
      lat: c.lat as number,
      lng: c.lng as number,
      distanceMeters: c.distanceMeters as number,
      confidence: c.confidence,
    }));

  return new Response(JSON.stringify({ candidates: ranked }), {
    status: 200,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
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

  const apiKey = Deno.env.get("GOOGLE_PLACES_API_KEY");
  if (!apiKey) {
    return new Response(JSON.stringify({ error: "server_misconfigured" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  if (bodyJson["mode"] === "nearby_candidates") {
    return handleNearbyMode(bodyJson, apiKey);
  }

  if (bodyJson["mode"] === "place_photos") {
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!serviceRoleKey) {
      return new Response(JSON.stringify({ error: "server_misconfigured" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    return handlePlacePhotosMode(bodyJson, apiKey, supabaseUrl, serviceRoleKey);
  }

  // Default: text search (existing behaviour).
  const query = bodyJson["query"];
  const lat = bodyJson["lat"];
  const lng = bodyJson["lng"];

  if (!query || typeof query !== "string" || query.trim().length === 0) {
    return new Response(JSON.stringify({ error: "bad_request" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const placesBody: Record<string, unknown> = {
    textQuery: query.trim(),
    languageCode: "ms",
    regionCode: "MY",
    maxResultCount: 8,
  };
  if (typeof lat === "number" && typeof lng === "number") {
    placesBody.locationBias = {
      circle: { center: { latitude: lat, longitude: lng }, radius: 250.0 },
    };
  }

  const resp = await fetch(
    "https://places.googleapis.com/v1/places:searchText",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": apiKey,
        "X-Goog-FieldMask":
          "places.id,places.displayName,places.formattedAddress,places.location",
      },
      body: JSON.stringify(placesBody),
    },
  );

  const json = await resp.json();
  return new Response(JSON.stringify(json), {
    status: resp.ok ? 200 : 502,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});
