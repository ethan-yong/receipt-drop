import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

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

  const placesBody: Record<string, unknown> = {
    textQuery: searchText,
    languageCode: "ms",
    regionCode: "MY",
    maxResultCount: 8,
  };
  const shareLat = row.share_location_lat;
  const shareLng = row.share_location_lng;
  if (typeof shareLat === "number" && typeof shareLng === "number") {
    placesBody.locationBias = {
      circle: {
        center: { latitude: shareLat, longitude: shareLng },
        radius: 250.0,
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
          "X-Goog-FieldMask":
            "places.id,places.displayName,places.formattedAddress,places.location",
        },
        body: JSON.stringify(placesBody),
      },
    );

    if (!resp.ok) {
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

    const json = (await resp.json()) as {
      places?: Array<{
        id?: string;
        displayName?: { text?: string } | string;
        location?: { latitude?: number; longitude?: number };
      }>;
    };

    const first = json.places?.[0];
    if (!first) {
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

    const placeGoogleId = first.id
      ? stripPlacesResourcePrefix(first.id)
      : null;

    const { error: upErr } = await supabase
      .from("transactions")
      .update({
        merchant_normalized: normalizeMerchant(merchantRaw),
        place_google_place_id: placeGoogleId,
        place_name: placeDisplayName(first),
        place_lat: first.location?.latitude ?? null,
        place_lng: first.location?.longitude ?? null,
        place_confidence: 0.85,
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

    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch {
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
});
