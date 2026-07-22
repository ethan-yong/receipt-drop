# Pending tasks

Backlog of planned work not yet implemented in the main app pipeline.

---

_Add new pending tasks below as separate `##` sections._

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
