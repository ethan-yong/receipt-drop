# Decisions log (ADR-style)

Newest first. Each entry: decision, reason, alternatives considered, tradeoffs. Derived from migration comments, code comments, and commit history — not all of these were written as formal ADRs at the time, so dates are approximate (from commit/migration timestamps).

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
