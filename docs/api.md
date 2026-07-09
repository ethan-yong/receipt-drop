# APIs & Services

Three server-side surfaces: Supabase Edge Functions (Deno, BFF/proxy layer), the self-hosted OCR API (Python/FastAPI), and the leaderboard API (Python/FastAPI + Redis). All are optional-at-different-degrees except the edge functions, which are load-bearing for enrichment and OCR-in-production.

## Auth flow (shared pattern)

Client (Flutter) holds a Supabase session (PKCE flow, see `lib/data/remote/supabase_client_holder.dart`). Every edge function call forwards the user's JWT as `Authorization: Bearer <token>`; each function constructs a `supabase-js` client scoped to that header (anon key + forwarded JWT, **not** service role) and calls `supabase.auth.getUser()` — 401 if missing/invalid. `enrich-transaction` additionally re-checks `row.user_id === user.id` after fetching by id (defense-in-depth beyond RLS). The leaderboard API decodes the same Supabase JWT **locally** (HS256, `SUPABASE_JWT_SECRET`, audience `authenticated`) rather than calling Supabase — see below.

## Supabase Edge Functions (`supabase/functions/`)

### `enrich-transaction`
Invoked by `sync_worker_flutter.dart` right after a transaction row is uploaded (skipped if `pipeline_status == 'needs_review'` — deferred until the user confirms via the review queue).

- Input: `{ transaction_id }`. Fetches the row (`raw_ocr_text`/`ocr_header_text`, `share_location_lat/lng`, `place_status`), then:
  - If `place_status == 'user_locked'`, skips everything else — just normalizes merchant text and marks `enriched` (respects a manual correction).
  - **LLM receipt understanding** (`supabase/functions/_shared/receipt_understanding.ts`): calls the self-hosted OpenAI-compatible gateway (`VLLM_*` env) with the row's OCR text (`raw_ocr_text`, falling back to `ocr_header_text`), gets back a structured `{merchant_name, merchant_search_queries, address_text, location_clues, vendor_category, google_place_types, confidence}`. **No fallback** — this is a testing-phase design decision: any LLM failure (timeout, non-2xx, unparseable JSON) writes `pipeline_status='failed_enrichment'` and `llm_understanding={_error, _raw, _meta}`, and the request stops there; it does **not** fall back to the old heuristic merchant-candidate matching. On success the structured output is persisted to `llm_understanding` (plus `_meta`: model/latency/prompt_source) and `merchant_normalized` is set from `merchant_name` before any Places call, so it's inspectable even if a later step fails.
  - **Alias fast-path**: computes a geohash bucket (precision 7) from `share_location_lat/lng` and checks `lookup_merchant_alias()` keyed on the **LLM's corrected merchant name** (not the raw OCR text — collapses OCR variants of the same merchant onto one cache key). On a hit, writes `place_*`/`pipeline_status='enriched'` directly from the cached row and returns — **no Google Places call at all**.
  - Otherwise calls Google Places API v1 **concurrently**: `places:searchText` for **up to 3** queries from `buildLlmTextQueries()` (the LLM's merchant search queries, plus one location-augmented variant, or an address+category-hint query when no merchant name was extracted) and one `places:searchNearby` (`includedTypes` from `resolveIncludedTypes()` — the LLM's own `google_place_types` when valid, else a vendor-category default, else `DEFAULT_NEARBY_TYPES`), using `supabase/functions/_shared/place_matching.ts`.
  - Merges candidates by place id (field mask now includes `places.types`), scores each via `scoreCandidate()` — `diceCoefficient` against the **best-matching** queried text, blended with `distanceScore(haversineMeters(...))` — then `adjustScoreForTypeMatch()` multiplies the score by 0.6 when the candidate's Places types share nothing with the LLM's expected `google_place_types` (keeps a same-block Nike Store from outscoring a food candidate on a food receipt). The "is merchant text usable" gate feeding the text/distance weight split requires the LLM's own `confidence.merchant >= 0.6`.
  - Writes back `merchant_normalized` (from the LLM), `place_*`, `place_status='guess'`, `pipeline_status='enriched'` — or `'failed_enrichment'` on any failure path (no API key, no search signal, no candidates, both searches fail).
  - **Alias write-back**: when the winning match's confidence clears `ALIAS_SAVE_CONFIDENCE_THRESHOLD` (0.85) and merchant text was usable, best-effort calls `upsert_merchant_alias()` keyed on the LLM's normalized name, so the next scan of the same merchant near the same location hits the fast-path above instead.
- Requires env `GOOGLE_PLACES_API_KEY` (**undocumented in `.env.example`** — see `docs/database.md` known gap) and `VLLM_BASE_URL`/`VLLM_MODEL_NAME` (+ optional `VLLM_API_KEY`/`VLLM_REASONING_EFFORT`), templated in `supabase/functions/.env.example`.
- `merchant_candidates` (client-derived heuristic candidates) and `category_guess`/`category_confidence` are no longer read by this function — superseded by the LLM's own extraction. They're still synced and still used by `places-proxy`'s `nearby_candidates` mode.

### `ocr-proxy`
Invoked by `lib/features/share/ocr_pipeline_io.dart` in production, so the OCR shared secret never ships in the client binary.

- Input: raw image bytes as the request body, `Content-Type` one of `image/jpeg|png|webp`.
- Forwards to the self-hosted OCR API at `${OCR_SERVICE_URL}/ocr` with header `X-OCR-Secret: OCR_SERVICE_SECRET`, 8s timeout (`AbortController`).
- Pure proxy — no DB access. Returns the OCR API's JSON pass-through, or `upstream_timeout`/`upstream_unreachable` on failure.
- In debug/dev, Flutter can instead call the OCR API **directly** (skipping this proxy) via `Env.ocrApiUrl` + `Env.ocrSharedSecret` (dart-define/`.env` only — never bundled in release).

### `places-proxy`
Invoked by `lib/data/repositories/places_repository.dart` for both the manual text-search flow and the nearby-candidate picker.

**Mode: text search (default)** — `{ query, lat?, lng? }`. Calls Google Places `searchText` (optional 250m `locationBias`), returns the raw response pass-through. Does not write to the DB.

**Mode: nearby candidates** — `{ mode: 'nearby_candidates', lat, lng, candidates?, query?, category?, limit? }`. Fires concurrent `searchText` (first query from `buildTextSearchQueries(candidates, query, 2)`) + `searchNearby` (300m radius, `CATEGORY_TO_PLACE_TYPES[category]` types or `DEFAULT_NEARBY_TYPES`). Merges by place id, scores each via `scoreCandidate()` (same weights as `enrich-transaction`), returns top `limit` (default 5, max 10) ranked by confidence:
```json
{ "candidates": [{ "id", "name", "address", "lat", "lng", "distanceMeters", "confidence" }] }
```
`lat` and `lng` are required; `candidates` / `query` / `category` are optional. Used by `PlacePickerScreen` when the user taps the pencil icon next to the merchant name.

In both modes: client updates the transaction after the user confirms, calling `TransactionRepository.updateTransactionPlace()` which writes `place_status='user_locked'` and re-queues sync.

### `_shared/place_matching.ts`
Exports used by `enrich-transaction`: `SEARCH_RADIUS_METERS=300`, `isUsableMerchantText()` (rejects <4 alphanumeric chars), `diceCoefficient()`, `haversineMeters()`, `distanceScore()`, `CATEGORY_TO_PLACE_TYPES`, `DEFAULT_NEARBY_TYPES`.

### `_shared/receipt_understanding.ts`
The LLM receipt-understanding step used only by `enrich-transaction`. `callReceiptUnderstanding(cfg, ocrText, fetchFn?)` calls the OpenAI-compatible chat-completions endpoint (`response_format: json_object` as a hint, one retry without it on HTTP 400) and returns either `{ok:true, understanding, model, latencyMs}` or `{ok:false, error, raw, latencyMs}` — no further retry on any other failure. `parseReceiptUnderstanding(raw)` is the validation authority: strips `<think>` blocks/markdown fences, coerces every field, drops off-vocabulary categories/place-types, clamps confidences, dedupes/caps search queries at 3; returns `null` only when nothing actionable survives. `buildLlmTextQueries()` and `resolveIncludedTypes()` turn the validated understanding into Places `textQuery`/`includedTypes` inputs; `adjustScoreForTypeMatch()` penalizes type-mismatched candidates post-scoring. Unit-tested (no network) in `receipt_understanding.test.ts` against the same scenarios as the manual verification recipe below.

## OCR API (`services/ocr-api/`) — self-hosted, replaces on-device ML Kit

FastAPI + Tesseract (via `pytesseract`), **not** PaddleOCR — an earlier PaddleOCR-based engine was replaced (see `docs/decisions.md`).

| Method | Path | Auth | Purpose |
|---|---|---|---|
| GET | `/health` | none | `{"status": "ok"}` |
| POST | `/ocr` | `X-OCR-Secret` header (shared secret, `secrets.compare_digest`) | Body = raw image bytes (no multipart). Returns `{text: str, confidence: float}`. Errors: `400 empty_body`, `400 invalid_image`, `500 processing_failed`, `401 unauthorized`, `500 server_misconfigured` (secret unset). |

Auth model is intentionally a single shared secret, not per-user — the service is only ever called by the `ocr-proxy` edge function (or directly in local dev), never by end-user clients.

**Pipeline**: decode (OpenCV) → optional perspective correction (off by default, unreliable on cluttered backgrounds) → deskew (Otsu + `minAreaRect`, clamped ±15°) → upscale to `MIN_OCR_WIDTH` (2500px default) → grayscale → Tesseract (`--oem 3 --psm 6 -l eng+msa`) → word-level results grouped into lines by `(block,par,line)` → confidence calibrated through a sigmoid (midpoint 0.75, steepness 8.0, de-inflates Tesseract's skewed raw scores) → if calibrated confidence < 0.4, retries once with adaptive-threshold binarization and keeps whichever pass scored higher.

No CLAHE/pre-binarization by default — both were tuned for the old PaddleOCR engine and measured to *degrade* Tesseract results (Tesseract runs its own Otsu pass internally).

**Running it**: `uv run ocr-api` (`scripts/run_ocr_api.ps1`) — refuses to start if the port is already listening (real TCP connect probe, not a bind test, because Windows lets a second process bind an already-listening port) and points you at `scripts/stop_ocr_api.ps1` instead of silently starting a stale second instance. Dev default port **8081**; the Dockerfile's default (and `bin/process_receipts.dart`'s `--help` text) is **8080** — know the two conventions differ when debugging "wrong port" issues.

**Docker (dev)**: `docker compose -f docker-compose.dev.yml up --build` — bind-mounts `services/ocr-api/app` with uvicorn `--reload`, exposes **8081:8080**, loads `OCR_SHARED_SECRET` from root `.env`. When Supabase runs locally, set `OCR_SERVICE_URL=http://host.docker.internal:8081` in `supabase/functions/.env`.

**Docker (one-off)**: `docker build -t ocr-api services/ocr-api` then `docker run -p 8080:8080 -e OCR_SHARED_SECRET=<secret> ocr-api`.

Consumers: `lib/features/share/ocr_api_client.dart` (Flutter direct-call, dev only), `ocr-proxy` edge function (production path), `bin/process_receipts.dart` (batch CLI, calls it directly, never through the proxy).

## Leaderboard API (`services/leaderboard-api/`) — FastAPI + Redis

Optional. When `LEADERBOARD_API_URL` is unset in Flutter's `.env`, the Friends tab calls the Supabase `get_friend_leaderboard()` RPC directly instead; Global tab requires this API (no Postgres fallback).

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | no auth |
| GET | `/friends-leaderboard?fresh=false` | Bearer JWT. Cache-aside: reads `cache:friends:<user_id>` (Redis, 10s TTL) unless `fresh=true`; miss/fresh calls `get_friend_leaderboard()` RPC (see below) and repopulates the cache. |
| GET | `/leaderboard/global` | Bearer JWT. Top-100 from Redis ZSET `leaderboard:global` (`ZREVRANGE ... WITHSCORES`), hydrated with profile metadata from Postgres via `get_leaderboard_profiles_by_ids()`. Never cached (`cached` always `false`). |
| POST | `/leaderboard/score` | Bearer JWT. Reads caller's own `(current_streak, badge_count)` from Postgres (RLS-scoped), upserts into the Redis ZSET. `{"status": "no_profile"}` if the profile row doesn't exist yet. |

**Auth**: decodes the Supabase-issued JWT locally (HS256, `SUPABASE_JWT_SECRET`, requires `exp`+`sub`, audience `authenticated`) — no round-trip to Supabase.

**Postgres access**: `asyncpg` pool; every per-user query runs inside a transaction that sets `role authenticated` + `request.jwt.claim.sub/role` session config, so **Postgres RLS enforces access** — the service impersonates the JWT-authenticated role rather than bypassing via service-role.

**Score packing**: a single Redis ZSET score encodes both fields — `leaderboard_score(streak, badges) = streak * 1_000_000 + badges` (`app/global_leaderboard.py`) — ranks primarily by streak, tie-broken by badge count.

**Sync flow**: on startup, if the ZSET is empty, bulk-rebuilds from `list_leaderboard_scores()` (best-effort — wrapped in try/except so Redis/Postgres being down doesn't block boot). Steady-state, the Flutter app calls `POST /leaderboard/score` once per home-screen open to keep the caller's own ZSET entry fresh.

**Deployment**: `docker-compose.yml` at repo root runs `redis` (7-alpine, AOF persistence, 256mb LRU cap) + `leaderboard-api` (depends_on redis healthy; `DATABASE_URL` points at `host.docker.internal:54322`, i.e. the host's local Supabase Postgres). `ocr-api` is **not** in that compose file — use `docker compose -f docker-compose.dev.yml up --build` for dev (hot reload, port 8081), or run via `uv run ocr-api` / standalone Docker build.

## Integrations summary

| External service | Called from | Purpose |
|---|---|---|
| Google Places API v1 | `enrich-transaction`, `places-proxy` (edge functions only — key never in client) | Merchant → place resolution, manual place search |
| Tesseract (self-hosted) | `ocr-proxy` → `services/ocr-api`, or direct dev call | Receipt text extraction |
| LLM gateway (self-hosted, OpenAI-compatible) | `enrich-transaction` (`_shared/receipt_understanding.ts`) | Structures raw OCR text into merchant name/queries/address/category before Places matching. No fallback — a failed call fails the enrichment. |
| Redis | `services/leaderboard-api` | Global leaderboard ZSET + friends-leaderboard cache-aside |
| Supabase Auth | Flutter (PKCE), all server surfaces (JWT verification) | Identity |
| Supabase Storage | Flutter sync worker | `receipts` (private, per-user folder) and `config` (public) buckets |
