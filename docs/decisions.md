# Decisions log (ADR-style)

Newest first. Each entry: decision, reason, alternatives considered, tradeoffs. Derived from migration comments, code comments, and commit history — not all of these were written as formal ADRs at the time, so dates are approximate (from commit/migration timestamps).

---

## LLM call relocated from `enrich-transaction` to `services/ocr-api` (2026-07-10)

**Decision**: the LLM gateway call itself — prompt building, `response_format`/retry handling, and the authoritative parse/validate of the LLM's JSON — moved out of the Deno edge function (`supabase/functions/_shared/receipt_understanding.ts`) and into a new `POST /understand` endpoint on `services/ocr-api` (`app/receipt_understanding.py`). `enrich-transaction` now calls that endpoint with `{ocr_text}` over the same shared-secret auth `ocr-proxy` already uses (`OCR_SERVICE_URL`/`OCR_SERVICE_SECRET`), and re-validates the response through the same `parseReceiptUnderstanding()` as a cheap second line of defense. `VLLM_BASE_URL`/`VLLM_API_KEY`/`VLLM_MODEL_NAME`/`VLLM_REASONING_EFFORT` moved with it — no longer read by `enrich-transaction` at all, now read by `ocr-api` from the root `.env` (same loader `app/__main__.py` already uses for `OCR_SHARED_SECRET`). `httpx` moved from ocr-api's dev-only deps to its runtime deps; a shared `httpx.AsyncClient` is created once via FastAPI `lifespan` rather than per-request.

Everything downstream of the LLM call — `buildLlmTextQueries()`, `resolveIncludedTypes()`, `adjustScoreForTypeMatch()`, the alias-cache keying, the Google Places calls themselves — **stays in Deno**, since it's tightly coupled to the Places API request shape built in that same edge function. Only the "call an LLM and get back validated JSON" piece moved.

**Reason**: requested directly — consolidate the one self-hosted external dependency (the LLM gateway) behind the one self-hosted service that already owns "turn a receipt into text/structure" (`ocr-api`), rather than having two Supabase-side surfaces (`enrich-transaction` and, previously, nothing) each independently reaching out to infrastructure outside Supabase. This also mirrors the existing `ocr-proxy` → `ocr-api` precedent instead of introducing a second, differently-shaped kind of external call from an edge function.

**Alternatives considered**: (a) keep calling the LLM gateway directly from `enrich-transaction` (the 2026-07-09 design) — rejected per this request; also had a latent deploy-reachability problem worth noting regardless: a `VLLM_BASE_URL` pointing at a LAN address (e.g. `192.168.2.134`) is reachable from the local `supabase start` Docker container but **not** from Supabase's hosted cloud once `supabase functions deploy` is used — moving the call into `ocr-api` doesn't eliminate that constraint, but it does mean there's only *one* self-hosted reachability concern (`OCR_SERVICE_URL`) instead of two. (b) do the LLM call at OCR/capture time (client-triggered, synchronous with `/ocr`) — rejected: would block the local-first "instant save" capture UX on LLM latency and couple OCR and understanding into one request; `enrich-transaction` calling `/understand` as a separate, later, async step keeps the timing identical to the previous design. (c) move the Places-query-building helpers (`buildLlmTextQueries` etc.) into Python too — rejected as out of scope; they don't touch the LLM, they shape the Google Places request that stays in Deno, moving them would just require translating back and forth.

**Tradeoffs**: `enrich-transaction`'s `llm_understanding._meta` no longer records which model produced a result (dropped the `model` field rather than adding new API surface just for a debug label) — the model name is discoverable from `ocr-api`'s own request logs (`model=%s` in `call_receipt_understanding`'s log line) instead. `ALLOWED_PLACE_TYPES`/`VENDOR_CATEGORIES`/the system prompt now exist in **two** places (`receipt_understanding.ts` and `receipt_understanding.py`) that must be kept in sync by hand — same "two ports of one algorithm" risk already documented for the Dart/TS geohash encoder (`memory/dependency_graph.md`), now with a second instance. `enrich-transaction`'s wall-clock budget grew by one more network hop (edge function → ocr-api → LLM gateway, vs. edge function → LLM gateway directly) — `UNDERSTAND_TIMEOUT_MS` (30s) in Deno is set comfortably above ocr-api's own `LLM_TIMEOUT_SECONDS` (25s) so a slow-but-successful call isn't cut off by the outer timeout first.

---

## LLM receipt-understanding step in `enrich-transaction`, no heuristic fallback (2026-07-09)

**Decision**: inserted an LLM step (`supabase/functions/_shared/receipt_understanding.ts`) between OCR text and Google Places matching, server-side inside `enrich-transaction`. It calls a self-hosted OpenAI-compatible gateway (`VLLM_BASE_URL`/`VLLM_API_KEY`/`VLLM_MODEL_NAME`/`VLLM_REASONING_EFFORT`) with the row's OCR text and gets back a structured, validated `{merchant_name, merchant_search_queries, address_text, location_clues, vendor_category, google_place_types, confidence}`, which replaces `merchant_candidates`/`category_guess` as the input to Places text/nearby search. The result is persisted to a new `transactions.llm_understanding jsonb` column (`20260709000000_llm_understanding.sql`) for debuggability. **Every enrichment goes through the LLM — there is deliberately no fallback to the old heuristic merchant-candidate matching during this testing phase**: an LLM failure (timeout, non-2xx, unparseable JSON) marks `pipeline_status='failed_enrichment'` and stops, the same way a Places-call failure already did.

The merchant-alias fast-path (`lookup_merchant_alias`/`upsert_merchant_alias`) moved to run *after* the LLM call and is now keyed on the LLM's corrected merchant name instead of the raw heuristic candidate text — OCR variants of the same merchant ("RESTORAN ANWAR MAU" / "RESTORAN ANWAR MAJU") now collapse onto one alias key instead of two. Existing alias rows keyed under the old scheme simply miss once and get repopulated.

`raw_ocr_text` is now always kept by the client (`ReceiptIngestService`, capped ~8000 chars) instead of only for failed/low-confidence parses, since the LLM needs the full receipt body — not just the merchant header — to infer category from line items (e.g. shampoo+milk+bread ⇒ groceries even when the shop name is unreadable).

**Reason**: this deliberately revisits the 2026-07-01-ish "heuristics over LLM" call recorded in `memory/experiments.md` for the parse pipeline — but scoped narrowly to *merchant understanding for Places matching*, not receipt parsing in general (amount/line-item extraction stays heuristic). pytesseract still produces subtly wrong merchant names (the same "RESTORAN ANWAR MAU" example from the 2026-07-08 alias-cache entry below), and an LLM correcting spelling + inferring category/address context from the whole receipt materially improves Places match quality beyond what dice-coefficient text matching over raw OCR candidates can do alone.

**Alternatives considered**: (a) run the LLM client-side in the parse pipeline before save — rejected for this testing phase: it would block capture UX on LLM latency, force `parseReceiptOcrText` async (rippling through `receipt_parse_file.dart` and the batch CLI), and need a new Drift column + sync mapping; running it server-side in `enrich-transaction` (already an async, fire-and-forget step) is a much smaller change. (b) fall back to the heuristic merchant-candidate matching when the LLM call fails — rejected explicitly per this testing phase's requirement that every enrichment prove the LLM path end-to-end; a silent fallback would mask gateway/prompt problems instead of surfacing them as `failed_enrichment`. (c) keep the alias cache keyed on raw OCR text — rejected in favor of the LLM's canonical name, since it's a strictly better cache key (collapses more OCR variants) and the LLM call already happens on every request regardless.

**Tradeoffs**: every enrichment now has an LLM round-trip on the critical path (up to `LLM_TIMEOUT_MS` = 25s) with zero fallback, so a gateway outage stalls *all* enrichment (not just a quality degradation) until it recovers — acceptable for this testing phase, not for production without revisiting. `google_place_types`/`vendor_category` from the LLM are validated against closed whitelists (`ALLOWED_PLACE_TYPES`, `VENDOR_CATEGORIES`) and off-vocabulary values are silently dropped rather than surfaced — a systematically-wrong prompt could quietly degrade to the `DEFAULT_NEARBY_TYPES` fallback with no visible error. `llm_understanding` is a debugging jsonb blob, not a queryable structured column — fine for testing-phase inspection, would want dedicated columns/indexes if this becomes long-term analytics.

---

## Back to `google_maps_flutter`, replacing flutter_map + CARTO (2026-07-09)

**Decision**: `spend_map_screen.dart` and `place_picker_screen.dart` moved from `flutter_map` + free CARTO Voyager tiles back to `google_maps_flutter`, reversing the 2026-07-06 entry below. `flutter_map`, `flutter_map_cancellable_tile_provider`, and `latlong2` are removed from `pubspec.yaml`; `google_maps_flutter`'s own `LatLng` is used everywhere.

**Reason**: the original 2026-07-06 swap was driven purely by the Maps SDK rendering blank (the GCP project had the Maps API enabled but no billing account attached). Billing is now enabled, so that blocker is resolved, and the product wants real Google Maps rendering (base map, attribution, and eventual parity with Google Places data) rather than the CARTO free tier, which was already flagged as not production-safe at scale.

**Key implementation choices**:
- **Screen-coordinate overlay for custom pins**: `google_maps_flutter`'s native `Marker` only accepts a static `BitmapDescriptor`, not a widget child, so `spend_map_screen.dart`'s custom `SpendPlaceMarker`/`FriendMapMarker`/"you are here" widgets are kept as real Flutter widgets, positioned in a `Stack` above the `GoogleMap` and reprojected via `GoogleMapController.getScreenCoordinate`/`getLatLng` on camera move (coalesced to one batched platform-channel call per frame, not one per pin per tick) and whenever the underlying pin data changes. `place_picker_screen.dart`'s simpler pins use native `Marker`s with `BitmapDescriptor.defaultMarkerWithHue` instead, since they're plain colored pins with no custom widget content.
- **Native API keys, not `.env`**: `google_maps_flutter` needs the key wired natively before Dart even runs. Android reads `MAPS_API_KEY` from `android/local.properties` (gitignored) via `build.gradle.kts` → `manifestPlaceholders`; iOS reads it from a new gitignored `ios/Flutter/Secrets.xcconfig` (`#include?`-ed from `Debug.xcconfig`/`Release.xcconfig`, template in `Secrets.xcconfig.example`) → `Info.plist`'s `GMSApiKey` → `AppDelegate.swift`'s `GMSServices.provideAPIKey(...)`. Both default to an empty/missing key building successfully with a blank map, rather than failing the build — same "degrade gracefully" shape as the original blank-map incident, just intentional this time.
- **Pin-shift-on-tap math reimplemented client-side**: the "shift the tapped pin up 25% of the viewport" trick (so the place-detail panel doesn't cover it) previously used flutter_map's synchronous `MapCamera.projectAtZoom`/`unprojectAtZoom`. `google_maps_flutter` has no client-side projection helper, so the standard Web Mercator tile math is reimplemented directly (`_mercatorProject`/`_mercatorUnproject` in `spend_map_screen.dart`) rather than using the async `getScreenCoordinate`/`getLatLng` round trip — that pair is tied to the *current* camera/zoom, which would give a wrong answer when animating to a different target zoom.

**Alternatives considered**: rasterizing custom pins to `BitmapDescriptor` bitmaps for true native `Marker`s — rejected for `spend_map_screen.dart`'s pins specifically, since it would need a new per-style rendering/caching layer for widgets that change per-cluster (amount, visit count) and per-friend (avatar config, mood); the screen-coordinate overlay keeps the existing widgets untouched.

**Tradeoffs**: the overlay approach has no built-in platform-view hit-testing or occlusion — tap handling is each widget's own `GestureDetector`, and pin positions can show a brief single-frame lag relative to the base map during very fast drags before the next batched reprojection lands. `spend_map_screen.dart` has no widget test (constructing a real `GoogleMap` platform view in `flutter_test` isn't supported without a hand-rolled fake `GoogleMapsFlutterPlatform`, which has no precedent here and wasn't worth adding) — its correctness rests on manual device/emulator verification, not automated coverage. `place_picker_screen.dart`'s `@visibleForTesting TileProvider? tileProvider` seam was replaced with `Widget? mapOverride` so its existing test suite could keep running without a real platform view.

---

## Receipt-flow design handoff: confirmation sheet + location picker restyle (2026-07-09)

**Decision**: implemented the two high-fidelity screens from the design handoff bundle (checked in at `docs/design/design_handoff_receipt_flows/` — moved there from the untracked `# Budget App Room Backgrounds/` folder it arrived in):

1. **`ReceiptConfirmSheet`** (`lib/features/share/receipt_confirm_sheet.dart`) replaces the read-only `ReceiptSummaryCard` as the post-OCR confirmation step. New behaviors: per-item include/exclude checkboxes with a live-recalculating total, a 4-second Undo banner after an exclusion, and inline vendor rename via the pencil button. `show()` returns an edited `ReceiptIngestDraft?` (null = cancelled) instead of the old bool; the edited draft flows into the unchanged `ShareSaveSheet`. `ReceiptIngestDraft.copyWith` gained `lineItems` for this.
2. **`PlacePickerScreen`** restyled in place: full-bleed map with a 300 m radius ring (mirrors `SEARCH_RADIUS_METERS` in `place_matching.ts`), gold/neutral candidate pins, a floating back button + search pill, a styled pull-up sheet with a 550 ms slide-up entrance, and an **in-sheet search mode** wired to `PlacesRepository.search` (a picked search result is promoted into the candidate list and selected). The empty-state "Search by name instead" now opens that in-sheet search instead of popping null. Fetch/testability hooks (`candidatesFetcher`, `tileProvider`, new `searchFetcher`) and the `push()` contract are unchanged.

Both screens use their own design language — Baloo 2 (google_fonts) plus a cream/gold token set in `lib/core/theme/receipt_sheet_theme.dart`, shared primitives in `lib/widgets/receipt_sheet_widgets.dart` — per the handoff's "high-fidelity, colors/type/spacing are final" instruction, deliberately distinct from the app-wide Plus Jakarta Sans theme. `AdaptiveSheet.showForm` gained optional `backgroundColor`/`topRadius`/`showDragHandle` (all backward compatible) to host the 28 px cream sheet.

**Reason**: the confirmation step previously offered no way to fix a wrong item list or vendor name without going through the full edit flow, and the picker was plain Material. The handoff mandated pixel-close recreation as Flutter widgets (explicitly not a WebView embed).

**Alternatives considered**: (a) mapping the handoff palette onto the existing `AppColors` theme — rejected, the README marks the tokens as final; (b) total = sum of checked items (the design demo's literal formula) — rejected in favor of *parsed OCR total minus excluded items' prices*, identical when items sum to the total but preserves tax/service charge when they don't; (c) drawing the 500 m ring from the handoff's demo copy — rejected, the ring shows the 300 m radius the backend actually searches.

**Tradeoffs**: two type systems now coexist (Baloo 2 receipt-flow sheets vs Plus Jakarta everywhere else) — if this design language later rolls out app-wide, `receipt_sheet_theme.dart` is the seed. `debugReceiptSheetSystemFont` mirrors the `buildReceiptDropTestTheme` convention to keep Google Fonts fetches out of widget tests — set it in any new test touching these screens. Item exclusions are applied destructively at commit (excluded rows are dropped from the draft, not stored as excluded). The map attribution widget is now visually covered by the full-bleed sheet.

---

## Post-OCR vendor location picker (2026-07-08)

**Decision**: Added a full-screen Grab-style place picker (`PlacePickerScreen`) accessible via a pencil icon next to the merchant name on the save sheet (pre-save) and the Change place button on transaction detail (post-save). The picker shows ≤5 nearby place candidates ranked by the same text+distance scoring enrichment uses; tapping a row animates the map camera and drops a red pin; Confirm writes `place_status='user_locked'`. Three architecture choices were made:

1. **Full-screen route over DraggableScrollableSheet**: flutter_map pan gestures conflict with sheet drag — a sheet containing a map requires extensive `RawGestureDetector` plumbing to prevent accidental dismissal. A `MaterialPageRoute(fullscreenDialog: true)` pushed via `Navigator.of(context, rootNavigator: true)` avoids the conflict entirely and can be called from inside a modal sheet.

2. **Extend `places-proxy` over a new Edge Function**: both text-search and nearby-candidates share the same auth/CORS/env-var boilerplate (~30 lines). Adding a `mode` discriminator keeps deployment surface minimal and co-locates all Google Places calls in one function. The actual scoring imports from `_shared/place_matching.ts` as before — no logic duplication.

3. **On-demand fetch (Option A) over persisting candidates (Option B)**: no schema change required; the picker is opened infrequently and network latency is acceptable for a user-initiated interaction. Option B (persist `place_candidates jsonb` on the transaction from enrichment) is deferred — it would add value for offline or repeat use but adds a migration, sync logic, and freshness concerns.

**Related change**: `TransactionRepository.updateTransactionPlace()` is a new dedicated method that sets `placeStatus='user_locked'` and re-queues sync — intentionally separate from `updateTransaction()`, which omits place-status and sync to avoid inadvertently overriding enrichment on every category/amount edit.

---

## Merchant candidates ranked by visual prominence (bounding-box height) (2026-07-08)

**Decision**: the self-hosted OCR API's `run_ocr()` (single flat `(text, confidence)` return) became a thin backward-compatible wrapper over a new `run_ocr_detailed()`, which returns per-line results carrying `height_ratio` (median word bounding-box height on that line, divided by the image's total height — from `pytesseract.image_to_data`'s existing box data, never previously surfaced past `ocr_engine.py`). This threads through `OcrResponse.lines` → `OcrApiResult.lines` → `OcrFileResult.lines` → `parseReceiptOcrText(ocrLines: ...)` into `extractMerchantCandidates()`, which gained a `'largeText'` candidate tier: a line with no keyword match but a height clearing 1.4x the receipt's median line height is treated as a likely header/logo line.

**Reason**: this was the deferred "real font-size signal" item from `pending-tasks.md`, recorded when the merchant-candidate ranking work only had position/keyword signals available. A receipt's merchant name is very often printed larger than the itemized body — a real visual cue a human uses instinctively that pure text heuristics can't see.

**Alternatives considered**: (a) an absolute pixel-height threshold — rejected, meaningless across receipts scanned at different resolutions/distances; used a receipt-relative ratio instead (line height ÷ that same image's height, baseline = median of that receipt's own lines). (b) Change `run_ocr()`'s return type in place (3-tuple) — rejected in favor of the same "new richer function, old one becomes a thin wrapper" pattern already used twice this session (`extractMerchant`/`extractMerchantCandidates`), so every existing test/call site needed zero changes. (c) Persist the per-line height data server-side (new `transactions`/Drift column) — rejected; it's consumed entirely client-side to rank candidates and doesn't need to outlive that computation, so no new migration was needed.

**Tradeoffs**: the large-text tier runs after the category-keyword and business-word-hint passes (so an exact brand match still wins outright) and before the position/letter-count fallback — a large-font line only matters when nothing recognized it by name. Threshold (1.4x median) and confidence (0.80) are tuning constants, same "tune after batch runs" caveat as `rm_amount_parser.dart`'s heuristics — no real-world batch data has validated these yet beyond the unit-test fixtures.

## Ranked merchant candidates + a global merchant-alias cache (2026-07-08)

**Decision**: `extractMerchant()` (single best guess) became a thin wrapper over `extractMerchantCandidates()`, which returns a ranked `List<MerchantCandidate>` (`{text, confidence, source}`) instead. The wider list — plus a longer 15-line scan window (was 8) and new phone/date/address/tax-ID exclusion filters — is synced to Postgres (`transactions.merchant_candidates`, `ocr_header_text`) and used by `enrich-transaction` to run up to 2 concurrent Google Places text-search queries instead of one. A new global `merchant_aliases` table (keyed by normalized merchant text + a coarse geohash bucket, accessed only through `lookup_merchant_alias()`/`upsert_merchant_alias()`) caches high-confidence resolutions so a repeat scan of the same merchant near the same place skips Google Places entirely.

**Reason**: pytesseract often produces a subtly wrong merchant name (e.g. `"RESTORAN ANWAR MAU"` for the real `"Restoran Anwar Maju"`), and handing Google Places only one OCR guess as the sole text signal means one bad extraction sinks the whole match. Ranking multiple candidates and trying more than one against Places materially improves match quality; caching a confirmed resolution turns every *repeat* visit to the same place into a free, instant, Places-quota-free lookup.

**Alternatives considered**: (a) keep a single merchant guess and rely entirely on GPS/distance scoring to compensate for bad OCR text — rejected, distance alone can't disambiguate between two nearby businesses; (b) scope the alias cache per-user — rejected in favor of global, since business names aren't sensitive per-user data and one user's correction should help every user who later visits the same place (same reasoning as the public `config` storage bucket); (c) literally match the numeric example weights given for "reliable vs. poor OCR text" scoring (0.5/0.5 vs 0.2/0.8) — rejected in favor of keeping the already-tuned `enrich-transaction` weights (0.6/0.4 vs 0.15/0.85, with caps) and only tightening the *gate* that selects between them, since there was no batch-run data to justify replacing already-reasoned constants; (d) extend the self-hosted OCR API to return per-line bounding-box/font-size data so candidates could be ranked by visual prominence ("large text") — deferred as a materially bigger cross-service change; recorded in `pending-tasks.md` rather than attempted here.

**Tradeoffs**: `merchant_aliases` is the first table in this schema where cross-user data sharing happens *outside* the friends/social system — worth remembering if its access pattern (definer-function-only, no direct table grants) ever needs revisiting. The wider 15-line merchant scan window now exactly matches `CategoryConfig.guessWithConfidence()`'s existing 15-line OCR-body scan depth, which means a category keyword deep in a receipt now *always* gets picked up by both (previously, an 8-vs-15 gap meant some receipts landed in the weaker "OCR-body-only" 0.55-confidence category tier instead of the full 0.85 "merchant-name" tier — this is a strict improvement, not a regression, but any test fixture that relied on that gap needed rewriting, see `test/receipt_parse_pipeline_test.dart`). Also surfaced and fixed in the same pass: `SyncWorker` was invoking `enrich-transaction` but never reading back its results (`place_name` et al. updated in Postgres, never written to the local outbox — see `memory/bugs.md`), and `category_confidence` was never synced from the client at all, silently disabling `enrich-transaction`'s existing category-biased Nearby Search.

---

## Receipt review queue for low-confidence/failed OCR (2026-07-05)

**Decision**: add `pipeline_status='needs_review'`, plus `raw_ocr_text`, `ocr_service_confidence`, `line_items_confidence`, `parse_failure_reason` columns (`supabase/migrations/20260705000000_receipt_review_and_raw_ocr.sql`). Low-confidence/failed parses route to a dedicated review screen (`lib/features/review/receipt_review_screen.dart`) instead of the normal auto-save pipeline; enrichment is deferred until confirmed.

**Reason**: the original v1 principle was "no anxiety UI — confidence tunes the parser, not the user." That held for a while, but some fraction of receipts genuinely can't be auto-parsed. Rather than silently guessing wrong or nagging on every row, low-confidence receipts get a one-tap confirm step, and `raw_ocr_text` is retained (only for this bucket) as free labeled data for fixing parser rules later.

**Alternatives considered**: (a) keep auto-saving with a visible low-confidence badge — rejected, contradicts the "no anxiety UI" principle; (b) drop/discard unparseable receipts — rejected, the app's whole pitch is "capture must feel free," never losing a receipt.

**Tradeoffs**: adds a queue the user must periodically clear; adds two confidence signals (`ocr_confidence` = amount-extraction quality vs. `ocr_service_confidence` = scan quality) that are easy to conflate — a bug from exactly this conflation shipped and was fixed (see `receipt_parse_pipeline.dart:79-84`: an earlier version re-applied the OCR service's already-sigmoid-calibrated confidence, crushing 0.34 down to ~0.036 and forcing every receipt into review regardless of actual quality).

---

## Self-hosted Tesseract OCR API, replacing on-device ML Kit (2026-07-01 to 07-02)

**Decision**: OCR moved from on-device Google ML Kit Text Recognition to a self-hosted `services/ocr-api` (FastAPI + `pytesseract`/Tesseract), called via the `ocr-proxy` Edge Function in production or directly in dev.

**Reason**: v1 spec originally chose on-device ML Kit specifically to avoid server-side re-OCR. That changed — likely to get consistent, tunable preprocessing (deskew, upscale, calibrated confidence, low-confidence retry) across all devices rather than depending on each OEM's ML Kit build, and to support desktop/CLI batch processing (`bin/process_receipts.dart`) against the same engine used in production.

**Alternatives considered**: PaddleOCR was tried first (`services/ocr-api` was originally built around it — comments in `preprocessing.py` explicitly note that CLAHE/pre-binarization steps were "tuned for the old PaddleOCR engine" and measured to *degrade* Tesseract results) and replaced with Tesseract.

**Tradeoffs**: now requires running/deploying a stateful service (vs. zero server cost with on-device ML Kit); adds a network hop and the shared-secret auth surface (`ocr-proxy`); gains cross-platform consistency, Malay-language support (`eng+msa`), and testability (real OpenCV preprocessing tests, mocked Tesseract call for unit tests).

---

## Two leaderboard systems: Postgres RPC (friends) + Redis ZSET (global) (2026-06-26 to 06-30)

**Decision**: friends leaderboard stays a Postgres `security invoker` RPC (`get_friend_leaderboard()`) reading live under RLS; a separate global leaderboard (`services/leaderboard-api`) ranks *all* users in a Redis ZSET, periodically rehydrated from two narrow, superuser-only Postgres functions.

**Reason**: friend groups are small — a live RLS-scoped Postgres query is fast enough and always fresh. A global "everyone" leaderboard doesn't scale the same way and doesn't need per-request freshness, so it's cached in Redis and only re-synced on score-changing events (`POST /leaderboard/score`, called once per home-screen open).

**Alternatives considered**: one unified Postgres-only leaderboard for both — likely rejected on scale/latency grounds as the user base target is "everyone," not just friend groups.

**Tradeoffs**: two code paths to reason about; the `get_friend_leaderboard()` function's security mode had to change from `definer` to `invoker` (`20260630000000_leaderboard_api.sql`) specifically so the external FastAPI service (impersonating users via JWT, not running as a Postgres superuser) could reuse it — which in turn required **widening `profiles` RLS** with a new `profiles_select_accepted_friend` policy, a deliberate departure from the earlier stated philosophy ("cross-user reads are never granted directly on a table... funneled through narrow security-definer functions," `20260626000002_social.sql`). This is a real widening of blast radius on `profiles` worth remembering when reasoning about who can read what.

---

## Impact Drops as a frozen design reference, not a shared codebase (2026-06-26)

**Decision**: import a Lovable-generated React/TanStack Start prototype (`Impact Drops/`) wholesale as a single commit, use it purely as a clickable design/behavior reference, then hand-port specific pieces (avatar, badges, diorama scenes, feed reactions, leaderboard labels, color/type tokens) into real Dart code operating on real data — never build, deploy, or import it as a dependency of the shipped app.

**Reason**: fast way to explore a gamification-heavy visual direction (3D diorama scenes, hex badges, blob avatar) without hand-designing it in Flutter from scratch, while keeping the real app's data model (Supabase-backed, RLS-scoped) as the actual source of truth.

**Alternatives considered**: building the gamification UI directly in Flutter from written specs only — slower to iterate visually; embedding the React app as a WebView — rejected, adds a second runtime and breaks the native app's cohesion.

**Tradeoffs**: two "sources of truth" now exist for this design (see `memory/bugs.md` / risks) — the prototype has been frozen since its single commit while the Flutter port has already diverged (different category sets, different theme counts, a `.glb`/three.js exception in the prototype not mentioned in its own plan doc). Future agents must treat `Impact Drops/` as historical reference only and verify against current Flutter code/behavior, not assume parity.

---

## flutter_map + CARTO tiles, replacing Google Maps SDK (2026-07-06)

**Decision**: replace `google_maps_flutter` with `flutter_map` + free CARTO Voyager raster tiles (no API key required).

**Reason**: the map rendered blank on all platforms because `google_maps_flutter` never had a billed API key configured; rather than set up Google Maps billing, switched to a free tile provider. (See `[[map-flutter-map-migration]]` memory for the incident.)

**Alternatives considered**: configure and bill a Google Maps API key — rejected for cost/setup friction at this stage.

**Tradeoffs**: CARTO's free tier is explicitly flagged in code (`spend_map_screen.dart`) as **not production-safe at scale** — must swap to a keyed provider (MapTiler/Stadia mentioned) before real usage volume. Also required adding friend map pins (`get_friend_map_pins()` RPC, `20260706000000_friend_map_pins.sql`) and fixing a missing Android `INTERNET` permission that had left release builds with no network at all.

---

## Category/place data never blocks a receipt from counting (v1 spec, 2026-05-11, still honored)

**Decision**: a transaction with any non-null `amount_myr` always counts toward totals/aggregations, regardless of `pipeline_status` (even `failed_enrichment`). Only a null amount excludes a row.

**Reason**: enrichment failures (Places API down, no candidates, quota) are common and shouldn't silently make the user's spend total wrong or incomplete.

**Alternatives considered**: hide unenriched rows from dashboards until enrichment completes — rejected, breaks the "you see your expense the moment you share it" promise.

**Tradeoffs**: dashboard/map code must remember this exclusion rule is keyed on `amount_myr`, not `pipeline_status` (`TransactionView.includeInCharts` in `lib/domain/models/transaction_view.dart` encodes it correctly — don't reintroduce a status-based filter).

---

## Local-first outbox (Drift/SQLite) with background sync, cloud never a gatekeeper (v1 spec, 2026-05-11)

**Decision**: every capture writes to on-device SQLite first and returns immediately; a background sync worker (retried up to 5x, then marked `stuck`) uploads to Supabase asynchronously.

**Reason**: capture must feel instant and work offline — this is the app's core wedge (receipts are shareable everywhere, network or not).

**Alternatives considered**: write-through to Supabase synchronously on save — rejected, fails the "no blocking screens" principle and breaks offline capture entirely.

**Tradeoffs**: requires the `foo_io`/`foo_web` platform-split machinery throughout the data layer (Drift needs native SQLite bindings, unavailable on web) — see `docs/architecture.md`. Requires careful idempotent upserts (client-generated UUIDs) so retried syncs don't duplicate rows.
