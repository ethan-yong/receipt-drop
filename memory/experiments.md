# Experiments: approaches tried, results, why abandoned

## OCR engine: PaddleOCR → Tesseract

**Tried**: `services/ocr-api` was originally built around PaddleOCR, with a preprocessing pipeline (CLAHE contrast enhancement, pre-binarization) tuned for it.

**Result**: replaced with `pytesseract`/Tesseract. Comments in `services/ocr-api/ocr_api/preprocessing.py` explicitly note the CLAHE/pre-binarization steps were tuned for PaddleOCR and *measured* to degrade Tesseract's results (Tesseract runs its own Otsu thresholding internally, so pre-binarizing fought it). Those steps are now opt-in-only (`shadow_binarize`, `enhance_contrast`), not part of the default pipeline.

**Why abandoned**: not documented in-repo beyond the preprocessing tradeoff; likely accuracy/consistency/deployability reasons (see `docs/decisions.md`). If re-evaluating OCR engines again, don't reuse the old CLAHE-heavy preprocessing config without re-measuring against whatever new engine is tried.

## On-device ML Kit OCR → self-hosted OCR API

**Tried**: v1 spec's original design used on-device Google ML Kit Text Recognition v2, explicitly to avoid server-side re-OCR.

**Result**: replaced with a self-hosted service (see above). Confirmed via `pubspec.yaml` (zero `google_mlkit_*` deps) and stale `build/` artifacts that still reference the old ML Kit plugins (build-cache leftovers, not active).

**Why abandoned**: likely inconsistent OCR quality across device OEMs/ML Kit versions, and a desire to run the exact same engine in a desktop batch tool (`bin/process_receipts.dart`) for fixture-driven regression testing — something on-device OCR can't easily support. See `docs/decisions.md` for the tradeoffs (network dependency, shared-secret auth surface gained; cross-platform consistency and testability gained).

## Google Maps SDK → flutter_map + CARTO tiles

**Tried**: `google_maps_flutter` per the v1 spec.

**Result**: map rendered blank on all platforms because no billed Google Maps API key was ever configured. Replaced with `flutter_map` + free CARTO Voyager raster tiles (no key needed).

**Why abandoned**: cost/setup friction of getting a billed Google Maps key, not a technical limitation of the SDK itself. CARTO's free tier is explicitly flagged as **not** production-safe at scale (`spend_map_screen.dart` comment) — a future swap to a keyed provider (MapTiler/Stadia mentioned) is expected, not a settled decision.

**Side discovery during this migration**: release builds had no network at all due to a missing Android `INTERNET` permission — unrelated to the maps choice itself, but found while debugging the blank map.

## Impact Drops: throwaway React prototype for gamification UX

**Tried**: generated a full React/TanStack Start app via Lovable (`Impact Drops/`) to explore avatar customization, hex badges, 3D CSS diorama scenes, a friends feed, and a spending map — all against mock/in-memory data, no backend.

**Result**: imported as a single commit, used as a click-through design reference, then abandoned/frozen — no commits since. Selected pieces were hand-ported into Dart against real Supabase-backed data (avatar config, badge tiles, diorama themes redrawn as flat 2D instead of 3D CSS/Three.js, feed reactions, leaderboard label generation, color/typography tokens).

**Why "abandoned" (as a live codebase, not as a design reference)**: it served its purpose as a fast visual/behavioral prototype; continuing to develop two parallel implementations (React mock + Flutter real) wasn't worth maintaining once the Flutter port existed. It's intentionally left frozen rather than deleted, in case future design work wants to reference it again.

**Divergence since freezing**: the prototype's own plan doc (`.lovable/plan.md`) says the diorama is CSS-3D-only ("no three.js"), but the shipped prototype code added a three.js/`@react-three/fiber` exception (`GlbDiorama.tsx`) for the shopping theme — meaning even the prototype had drifted from its own design doc before the Flutter port was made. Don't trust `.lovable/plan.md` as an accurate description of `Impact Drops/`'s current code, and don't trust either as an accurate description of the current Flutter behavior.

## Receipt line-item extraction: heuristic-first (not LLM-based)

**Tried/decided** (see `pending-tasks.md`, now largely implemented): regex-cascade pattern matching for item/price pairs (`RM`-prefixed, quantity-prefixed, bare-decimal fallback), explicitly choosing heuristics over LLM-based parsing for v1.

**Result**: implemented in `lib/domain/logic/receipt_line_item_extractor.dart`, integrated into the parse pipeline, persisted via `receipt_line_items`/`OutboxLineItems`, surfaced on the receipt card.

**Why heuristics over LLM**: `pending-tasks.md` lists "LLM-based parsing" explicitly as out of scope for the initial task, prioritizing deterministic, testable, offline-capable extraction over per-request inference cost/latency/non-determinism. Worth remembering if a future request suggests "just use an LLM to parse the receipt" — that tradeoff was already considered and deliberately deferred, not overlooked.
