# Pending tasks

Backlog of planned work not yet implemented in the main app pipeline.

---

_Add new pending tasks below as separate `##` sections._

---

## Native Google Sign-In on iOS

Android now uses native `google_sign_in` (in-app Credential Manager sheet, no browser) — see 2026-07-31 entry in `docs/system/decisions.md`. iOS deliberately still uses the old `signInWithOAuth` browser-redirect flow, deferred because it needs its own Google Cloud OAuth client that doesn't exist yet (only the Web and Android clients do).

Design already worked out (was implemented and then reverted to Android-only — same shape should work when picked back up):

- Create an **iOS** OAuth client in Google Cloud Console (bundle ID `com.receiptdrop.receiptDrop`, from `PRODUCT_BUNDLE_IDENTIFIER` in `ios/Runner.xcodeproj/project.pbxproj`).
- `Env.googleIosClientId` getter in `lib/core/config/env.dart` (same `String.fromEnvironment` → `.env` pattern as `googleWebClientId`), reading a new `GOOGLE_IOS_CLIENT_ID` var.
- Pass it as `clientId` to `GoogleSignIn.instance.initialize()` in `lib/main.dart`, guarded for iOS (alongside the existing Android guard, using `Env.googleWebClientId` as `serverClientId` on both platforms).
- `ios/Flutter/Secrets.xcconfig` / `Secrets.xcconfig.example`: add `GOOGLE_IOS_REVERSED_CLIENT_ID = com.googleusercontent.apps.<id>` (mirrors the existing `MAPS_API_KEY` xcconfig substitution pattern).
- `ios/Runner/Info.plist`: add a second `CFBundleURLTypes` array entry with `CFBundleURLSchemes = ["$(GOOGLE_IOS_REVERSED_CLIENT_ID)"]`, alongside the existing `com.receiptdrop.receiptdrop` entry (don't reintroduce the duplicate-key bug that was fixed 2026-07-31 — one array, multiple dict entries).
- `supabase/config.toml`'s `[auth.external.google]` `client_id` needs both the Web and iOS client IDs to validate ID tokens from both platforms. `env()` only interpolates a whole field (no concatenation), so this means a new combined `.env` var (e.g. `GOOGLE_OAUTH_CLIENT_IDS`, comma-separated, web first) referenced as `client_id = "env(GOOGLE_OAUTH_CLIENT_IDS)"`, and `scripts/supabase_start.ps1` updated to export it. Mirror the same comma-separated list in the remote Supabase dashboard's Google provider settings (`setup.md`).
- Extend `_useNativeGoogle` in `lib/features/auth/auth_screen.dart` to include `TargetPlatform.iOS`.

---

## Strip demo receipts from Home

Remove seeded / sample transactions from the home receipt list so the carousel only shows the user’s real captures (`lib/data/repositories/demo_transactions.dart` and any home-screen seeder path).

---

## Profile highlight: receipt count + top badges

Surface personal stats on (or near) the profile/gamification surface: primary metric is **receipts owned**; beneath that, the user’s **top 3 earned badges**. Exact layout and copy still open — worth a short design pass before locking numbers vs badges priority.

Leaderboard rows already show top badges + `badge_score` pts; this task is specifically the personal/home profile highlight with receipt count as the hero number.

---

## Contextual “+” capture affordance

The floating “+” / add control currently appears too broadly. Show it only where capture or import is the natural next action; hide it on screens where it competes with primary content or has no useful target.

Still always shown in `lib/widgets/main_shell.dart`.

---

## Integrate sync animation from Claude design

Port the sync / processing motion from the Claude design handoff into the pending-import and sync UX so waiting for OCR feels intentional rather than a bare spinner.

---

## Grouped Home-carousel card for 6+ receipt batches

The save-success screen's "bag" variant (6+ receipts saved in one "Process
all" batch) shows one grouped "N receipts saved" badge, but the Home
carousel and `_TodayStrip` (`lib/features/save_success/save_success_screen.dart`)
still list each transaction individually — a known, intentional
inconsistency. Needs a grouped-card design (likely keyed by a shared
batch/import-session id) before it's resolved. See `docs/system/decisions.md`,
2026-07-22 "Save-success animation gets count-based variants" entry.

---

## Home screen spend statistics

**Future.** Add a lightweight statistics strip or section on Home (totals, trends, or category mix) so the first screen answers “how am I spending?” without opening another tab.

---

## Category splash gallery (collectible end-of-list)

**Future.** After the home receipt list, show a gallery of category splash cards. Unseen categories render as hidden / silhouette icons; uploading a receipt in that category reveals the art — a gentle collectible loop that nudges broader capture.

---

## Evolving category splash art

**Future.** As a category accumulates more uploads (per user or community — TBD), evolve that category’s splash art through progressive stages so repeat capture visibly “grows” the collection.

---

## Merchant-intelligence: skip Google Places calls for known locations

**Deferred, not pre-ship.** The merchant-intelligence layer (`docs/plans/2026-07-24-merchant-intelligence-layer.md`, `supabase/functions/_shared/merchant_resolution.ts`, `supabase/migrations/20260724030000_merchant_intelligence_reconciliation.sql`) as shipped still calls Google Places on every enrichment before it ever reconciles against the `merchants`/`merchant_locations` catalog — `decideMerchantResolution()` needs the Places winner's name/types to score brand-vs-place agreement, and `reconcile_merchant_resolution` needs the winner's `place_id`/lat/lng regardless of outcome. So today the catalog is purely a downstream bookkeeping/identity layer; it does not yet reduce Places API call volume or quota cost, even though `merchant_locations.hit_count` already tracks exactly the repeat-visit signal a Places-skip optimization would need.

**Why deferred**: no real production traffic exists yet to tell whether this is worth the risk. Skipping a live Places call on a `merchant_locations` hit means trusting a potentially-stale record — a business can close, move, or rebrand between visits, and `merchant_aliases`' existing decay/floor logic (`ALIAS_MIN_TRUST_CONFIDENCE`, see `supabase/functions/_shared/place_matching.ts`) exists precisely because that already happened enough to need a floor for the *cheaper* alias fast-path. A location-level skip is a bigger bet: it would remove the "does Places still agree this venue exists/serves the same category" check entirely for a hit, not just widen a cache. `supabase/scripts/20260724_merchant_intelligence_quality_report.sql` (added alongside the reconciliation RPCs) is meant to be run periodically once `MERCHANT_INTELLIGENCE_MODE=on` has accumulated real traffic — its hit-count/observation-count distributions and duplicate-merchant detector are the data this decision should be based on, not a guess made pre-launch.

**Proposed design sketch** (needs real usage data before being finalized, not ready to implement as-is):
- A second-tier fast path in `enrich-transaction`, analogous to the existing alias fast-path but keyed on `merchant_locations` (brand text + geohash bucket, via `lookup_merchant_candidates`'s existing trigram/alias-evidence query) instead of the exact-text `merchant_aliases` cache — only short-circuits Places when a candidate clears a *separate, likely higher* confidence floor than `ALIAS_MIN_TRUST_CONFIDENCE`, since a location skip is a stronger claim than an alias-text skip.
- A staleness re-verification requirement even on a hit — e.g. re-run a live Places call at most once every N days per `merchant_locations` row (tracked via a new `last_places_verified_at` column) regardless of `hit_count`, so a permanently-skipped location can never silently drift from reality (closed business, rebrand, category change).
- Ship behind its own separate flag from `MERCHANT_INTELLIGENCE_MODE`, gated on first observing at least one full rollout cycle of the reconciliation-only feature (no Places-call reduction) in production, per the quality-report script above.

---

<!--
DONE (2026-07-14, achievements branch): Achievements page with grounded badge design.
Tiered SVG achievements, Postgres-computed progress (`20260714000000_achievements.sql`,
`20260714000001_badge_score.sql`), streamed to `BadgesScreen` with
`AchievementProgressCard` tier cards. Catalog replaced emoji stubs.
-->

<!--
DONE (2026-07-14, achievements branch): Leaderboard redesign.
Ranks by `badge_score`; each row shows top achievement badge hexes
(`feat(leaderboard): rank by badge_score and show top achievement badges`).
-->

<!--
DONE (2026-07-12 / labeled 2026-07-14): Pending-import sync control (share → OCR).
OS share saves to local pending inbox; `PendingImportsScreen` has Process / Retry /
Process all; home banner links to the inbox. Merged via receipt-share-feat PR #11.
-->

<!--
DONE (2026-07-14, user-confirmed): Spend-map pin lag + pin labels.
Map markers were laggy while panning; pins now show spend summary with
receipt count (or inverse: count first, amount on tap). See map viewport /
clustering work around `spend_map_screen` and related pin widgets.
-->

<!--
DONE (2026-07-08, labeled 2026-07-14): Receipt line-item extraction (item + price pairs).
Implemented across the parse → persist → UI path:
- `lib/domain/logic/receipt_line_item_extractor.dart` + `lib/domain/models/receipt_line_item.dart`
- Wired into `receipt_parse_pipeline.dart` (heuristic + LLM understanding path)
- Drift `outbox_line_items` + Supabase `receipt_line_items` (20260703000000)
- `ReceiptCard` / `ReceiptConfirmSheet` render itemized rows; batch tool emits `lineItems`
- Tests: `test/receipt_line_item_extractor_test.dart`, confirm-sheet and card coverage
-->

<!--
DONE (2026-07-08): Post-OCR vendor location picker (Grab-style nearby suggestions).
Implemented as planned — `supabase/functions/places-proxy/index.ts` extended with
a `nearby_candidates` mode (concurrent searchText + searchNearby, same
`scoreCandidate()` scoring as enrichment, returns top-5 ranked candidates with
`{id, name, address, lat, lng, distanceMeters, confidence}`). New
`lib/features/places/place_picker_screen.dart` full-screen picker opened via
`PlacePickerScreen.push()` (rootNavigator, works from inside AdaptiveSheet modals).
Pencil icon added to `share_save_sheet.dart` / confirm sheet merchant row;
`_pickPlace()` in `transaction_detail_screen.dart` opens picker when location is
available, falls back to Places text search. `TransactionRepository.updateTransactionPlace()`
writes `placeStatus='user_locked'` and re-queues sync; `ingestReceipt()` also
handles pre-save user lock. ADR in `docs/decisions.md`, API docs in `docs/api.md`,
feature graph in `memory/feature_graph.md`.
-->

<!--
DONE (2026-07-08): Merchant candidate ranking: real font-size / bounding-box
signal. Implemented as planned — `services/ocr-api/app/ocr_engine.py` now
exposes `run_ocr_detailed()` returning per-line `height_ratio` (median word
bbox height / image height), threaded through `OcrResponse.lines` ->
`OcrApiResult.lines` -> `OcrFileResult.lines` -> `parseReceiptOcrText(ocrLines:
...)` -> `extractMerchantCandidates(ocrLines: ...)`, which adds a `'largeText'`
source tier (confidence 0.80, must clear 1.4x the receipt's median line
height) between the keyword tiers and the position fallback. Fully additive —
`null`/absent `ocrLines` behaves identically to before. See
`docs/decisions.md` for the ADR entry and `memory/feature_graph.md` for the
updated dependency list.
-->
