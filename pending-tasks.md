# Pending tasks

Backlog of planned work not yet implemented in the main app pipeline.

---

_Add new pending tasks below as separate `##` sections._

---

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
