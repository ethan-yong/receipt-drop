# APIs & Services

Three server-side surfaces: Supabase Edge Functions (Deno, BFF/proxy layer), the self-hosted OCR API (Python/FastAPI), and the leaderboard API (Python/FastAPI + Redis). All are optional-at-different-degrees except the edge functions, which are load-bearing for enrichment and OCR-in-production.

## Auth flow (shared pattern)

Client (Flutter) holds a Supabase session (PKCE flow, see `lib/data/remote/supabase_client_holder.dart`). Every edge function call forwards the user's JWT as `Authorization: Bearer <token>`; each function constructs a `supabase-js` client scoped to that header (anon key + forwarded JWT, **not** service role) and calls `supabase.auth.getUser()` — 401 if missing/invalid. `enrich-transaction` additionally re-checks `row.user_id === user.id` after fetching by id (defense-in-depth beyond RLS). The leaderboard API decodes the same Supabase JWT **locally** (HS256, `SUPABASE_JWT_SECRET`, audience `authenticated`) rather than calling Supabase — see below.

## Supabase Edge Functions (`supabase/functions/`)

### `enrich-transaction`
Invoked by `sync_worker_flutter.dart` right after a transaction row is uploaded (skipped if `pipeline_status == 'needs_review'` — deferred until the user confirms via the review queue).

- Input: `{ transaction_id }`. Fetches the row (including `merchant_candidates` and `ocr_header_text`, synced by the client alongside `merchant_raw`), then:
  - If `place_status == 'user_locked'`, skips Places entirely — just normalizes merchant text and marks `enriched` (respects a manual correction).
  - **Alias fast-path**: computes a geohash bucket (precision 7) from `share_location_lat/lng` and checks `lookup_merchant_alias()` for the top-ranked merchant candidate's normalized text. On a hit, writes `place_*`/`pipeline_status='enriched'` directly from the cached row and returns — **no Google Places call at all**.
  - Otherwise calls Google Places API v1 **concurrently**: `places:searchText` for **up to 2** distinct ranked merchant candidates (`buildTextSearchQueries()`, falling back to the single `merchant_raw`/`merchant_normalized` query when candidates are absent — e.g. rows synced before this shipped) and one `places:searchNearby` (`includedTypes` biased by `category_guess` via `CATEGORY_TO_PLACE_TYPES` when `category_confidence >= 0.5`, else `DEFAULT_NEARBY_TYPES`), using `supabase/functions/_shared/place_matching.ts`.
  - Merges candidates by place id, scores each via `scoreCandidate()` — `diceCoefficient` against the **best-matching** queried text (not just one), blended with `distanceScore(haversineMeters(...))` (exponential decay, ~0.37 at 150m). The "is OCR text usable" gate feeding the text/distance weight split now also requires the top merchant candidate's own extraction confidence to clear ~0.6 (when available), tightening the original length-only check.
  - Writes back `merchant_normalized`, `place_*`, `place_status='guess'`, `pipeline_status='enriched'` — or `'failed_enrichment'` on any failure path (no API key, no candidates, both searches fail).
  - **Alias write-back**: when the winning match's confidence clears `ALIAS_SAVE_CONFIDENCE_THRESHOLD` (0.85) and OCR text was usable, best-effort calls `upsert_merchant_alias()` so the next scan of the same merchant near the same location hits the fast-path above instead.
- Requires env `GOOGLE_PLACES_API_KEY` (**undocumented in `.env.example`** — see `docs/database.md` known gap).

### `ocr-proxy`
Invoked by `lib/features/share/ocr_pipeline_io.dart` in production, so the OCR shared secret never ships in the client binary.

- Input: raw image bytes as the request body, `Content-Type` one of `image/jpeg|png|webp`.
- Forwards to the self-hosted OCR API at `${OCR_SERVICE_URL}/ocr` with header `X-OCR-Secret: OCR_SERVICE_SECRET`, 8s timeout (`AbortController`).
- Pure proxy — no DB access. Returns the OCR API's JSON pass-through, or `upstream_timeout`/`upstream_unreachable` on failure.
- In debug/dev, Flutter can instead call the OCR API **directly** (skipping this proxy) via `Env.ocrApiUrl` + `Env.ocrSharedSecret` (dart-define/`.env` only — never bundled in release).

### `places-proxy`
Invoked by `lib/data/repositories/places_repository.dart` for the manual "change place" search flow.

- Input: `{ query, lat?, lng? }`. Calls Google Places `searchText` (optional 250m `locationBias`), returns the raw response pass-through. Does not write to the DB — the client updates the transaction after the user picks a candidate (setting `place_status='user_locked'`).

### `_shared/place_matching.ts`
Exports used by `enrich-transaction`: `SEARCH_RADIUS_METERS=300`, `isUsableMerchantText()` (rejects <4 alphanumeric chars), `diceCoefficient()`, `haversineMeters()`, `distanceScore()`, `CATEGORY_TO_PLACE_TYPES`, `DEFAULT_NEARBY_TYPES`.

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
| Redis | `services/leaderboard-api` | Global leaderboard ZSET + friends-leaderboard cache-aside |
| Supabase Auth | Flutter (PKCE), all server surfaces (JWT verification) | Identity |
| Supabase Storage | Flutter sync worker | `receipts` (private, per-user folder) and `config` (public) buckets |
