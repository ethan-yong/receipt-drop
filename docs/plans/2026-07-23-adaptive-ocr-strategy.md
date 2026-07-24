# Feature: Adaptive OCR Strategy Selection

## Overview

Replace the OCR API's single fixed Tesseract configuration (PSM 6, always) with a lightweight, heuristic, pre-OCR image classification step that selects a layout-appropriate segmentation strategy per receipt, and generalizes the existing single-retry mechanism into a classification-informed second pass with multi-signal result scoring. It targets receipts whose layout (multi-column, very sparse, unusually shaped) or whose specific failure mode (wrong segmentation vs genuine image-quality problem) the current fixed pipeline handles poorly, while staying within the same worst-case latency envelope as today's pipeline on the interactive capture path.

## Problem Statement

Three concrete gaps in the current pipeline (`services/ocr-api/ocr_api/ocr_engine.py`):

1. **One segmentation mode for every layout.** PSM 6 assumes a single uniform text block. Multi-column receipts (item name and price in visually separate columns) and very sparse receipts (short thermal slips, minimal bank/wallet confirmations) are both known-poor fits for PSM 6, but the pipeline never varies it.
2. **The retry can't distinguish "bad image" from "wrong config."** The only fallback today is "re-run the exact same PSM against a binarized image." If the real problem is segmentation-mode mismatch rather than contrast/shadow, binarizing doesn't help and wastes the one retry slot the latency budget allows.
3. **The keep-or-discard decision after retry only looks at confidence.** `run_ocr_detailed` keeps the retry result only if calibrated confidence improved — but Tesseract confidence is a per-word recognition score, not a correctness score. Binarization can raise raw confidence while destroying actual text fidelity (e.g., thin strokes lost to thresholding), and the current logic has no way to catch that.

## Goals

- Select a Tesseract PSM (and, when relevant, an image variant) based on measurable image/layout characteristics rather than a single hardcoded default.
- When a second pass is warranted, choose the fallback intelligently (alternate segmentation vs. binarized image) based on the failure signal, instead of always binarizing.
- Score OCR output using multiple cheap signals (amount detection, keyword presence, text coherence, line count, confidence) instead of confidence alone, so a higher-confidence-but-worse-text result is no longer preferred by accident.
- Preserve the existing worst-case latency ceiling on the interactive capture path (still ≤2 total Tesseract calls, same internal time-budget guard).
- Provide a separate, explicitly relaxed budget mode for offline/batch reprocessing where more passes are acceptable, using the existing dev batch tool as the evaluation harness.
- Ship behind a feature flag with a shadow-mode validation period before becoming the default, consistent with this codebase's established rollout pattern (`PREPROCESS_*`, `LLM_CLEANUP_ENABLED`).

## Non-Goals

- **No receipt *semantic* type classification** (restaurant vs. supermarket vs. bank slip). That information isn't knowable before OCR runs — it's a chicken-and-egg problem. This spec classifies visual/geometric image characteristics only (density, aspect ratio, region count, column presence), not receipt category. (This is a deliberate reframing of the original ask, which used "restaurant vs. supermarket" as an example; see Tradeoffs.)
- **No ML-based classifier or model.** Classification is heuristic (OpenCV feature extraction + a small decision table), matching the precedent set by `lib/domain/logic/receipt_layout_analyzer.dart`, which explicitly rejected an ML layout model.
- **No language auto-detection or dynamic language switching.** `TESSERACT_LANG` stays fixed at `eng+msa`; no evidence in `memory/bugs.md`/`memory/experiments.md` of a non-English-receipt problem to justify this scope.
- **No third preprocessing image variant.** Candidate images are limited to the two that already exist in `preprocessing.py` (the standard CLAHE'd grayscale, and `shadow_binarize`'s adaptive-threshold output). A third "enhanced contrast" variant is explicitly deferred (see Tradeoffs) pending evidence it's needed.
- **No per-pass LLM merchant-quality scoring.** The existing LLM receipt-understanding call still runs exactly once, after the final OCR result is chosen — not once per candidate pass. "Merchant extraction quality" in scoring is a cheap heuristic proxy, not real merchant extraction.
- **No cross-request caching.** Each receipt image is unique; there's no repeated input to cache against.
- **No change to the client-facing `OcrResponse` contract's existing fields' meaning** (`text`, `confidence`, `lines[].height_ratio/left_ratio/top_ratio/width_ratio`) — any new fields are additive and optional.

## Proposed Solution

Insert a cheap heuristic classification step between preprocessing and the first Tesseract call. The classifier extracts a small set of geometric/density features from the already-preprocessed grayscale image (text density via foreground-pixel ratio, aspect ratio, connected-component count, column presence via vertical projection-profile peak analysis, line density via horizontal projection-profile peaks) and maps them through a small static decision table to a strategy: which PSM to use, and which image variant to run it against. This replaces the current hardcoded PSM 6.

The existing single-retry mechanism is reworked, not replaced: it still fires under the same trigger (calibrated confidence below threshold) and the same time-budget guard, but the fallback it chooses is now classification-informed — if the classifier's own layout read was ambiguous (near a decision-table boundary), the second pass tries the alternate PSM on the same image; if the classifier's read was confident but Tesseract's result was still poor, the second pass binarizes (today's only behavior). Whichever of the two passes produces the higher composite score — not just higher confidence — is kept.

For batch/offline use (the existing dev batch tool, or future background reprocessing of `needs_review` items), a separate relaxed budget mode allows more candidate passes and is the mechanism by which the decision table and scoring weights get empirically tuned against a real receipt dataset before the interactive path's defaults are finalized.

## User Experience

This is a backend pipeline change with no new UI. The end-user-visible effects are indirect:

- **Happy path (unchanged in shape):** user shares/captures a receipt → local-first save happens immediately regardless of OCR outcome (existing architecture, untouched) → OCR completes in the same one-request-response-cycle as today, just with a layout-appropriate config chosen automatically. No visible difference from today's fast path.
- **Recovered path (improved):** receipts that previously fell into the single generic retry (always-binarize) now get a fallback chosen for the actual failure mode, so more of them should recover with usable text on the second pass. Still invisible to the user — surfaces as fewer transactions landing in the existing review queue.
- **Still-poor path (unchanged fallback):** if both passes score poorly, the existing `pipeline_status='needs_review'` mechanism (2026-07-05 ADR) is reused unchanged — this feature does not introduce a new user-facing error state.
- **Feedback mechanism:** none new for end users. For internal QA/debugging, new optional response fields (see Technical Design) let the batch tool and future admin tooling see which strategy/pass was chosen, without the app needing to change.

## System Impact

- **Backend services:** Primary impact is `services/ocr-api`. New classifier module, a small strategy decision table, a composite scoring function, and a reworked pass-control-flow inside `ocr_engine.py`'s `run_ocr_detailed`. `main.py`'s endpoint shape is unchanged — still one synchronous `POST /ocr` call.
- **Client application:** No required change. `lib/features/share/receipt_parse_pipeline.dart` and the Dart `OcrLine`/response mirror models are unaffected as long as new server fields are optional additions — the existing response-schema-stability test in `test_main.py` establishes this invariant must hold. Optional: the Dart mirror model could later add matching optional fields if the team wants to surface strategy/score info in debug tooling, not required for v1.
- **Database/storage:** None required. Reuses the existing `pipeline_status`/`ocr_service_confidence` columns for the still-poor-result path; no new tables needed for v1 (see Implementation Guidance for an optional future addition).
- **AI/ML pipeline:** No new model. The existing LLM understanding/cleanup call is untouched — still exactly one call, after the final OCR result is selected.
- **Infrastructure:** None — same self-hosted service, no new deployment surface, no new external dependency.
- **Dev tooling:** `bin/process_receipts.dart` / `scripts/process_receipts.ps1` gain the relaxed batch-mode budget, making them the harness for tuning this feature's decision table and score weights against a labeled dataset.

## Technical Design

**New component: characteristics classifier** (new module in `services/ocr-api/ocr_api/`, e.g. alongside `preprocessing.py`). A pure function taking the preprocessed grayscale image (the same image already produced by the existing `preprocess()` pipeline, post-CLAHE/illumination, pre-Tesseract) and returning a small feature set plus a strategy bucket. Features, all computed with vectorized OpenCV operations (no per-pixel Python loops, for latency):

- **Text density**: ratio of foreground (ink) pixels to total pixels after an Otsu threshold pass used only for measurement (not fed to Tesseract).
- **Aspect ratio**: width/height of the deskewed image (already available from the existing preprocessing step).
- **Region count**: connected-component count via `cv2.connectedComponentsWithStats` on the measurement threshold, as a proxy for text-block count.
- **Column presence**: vertical projection profile (column-wise sum of foreground pixels) — multiple distinct peaks separated by a sustained low-density gap indicates a multi-column layout.
- **Line density**: horizontal projection profile peak count and spacing, used to distinguish sparse vs. dense text.

**New component: strategy decision table.** A small static mapping (dict or equivalent, not a model) from feature-bucket combinations to a strategy record `{psm, image_variant}`. Starting buckets:

- Default/uniform block (most receipts: single dense column, no strong column signal) → PSM 6 (today's default, unchanged for the common case), standard image.
- Multi-column detected (sustained projection-profile gap splitting the width) → PSM 4 ("single column of variable-sized text" — still assumes single logical column, which fits a receipt's two-column *layout* better than PSM 6's uniform-block assumption; note as an assumption requiring empirical validation — see Testing Strategy).
- Very sparse (low text density, low region count) → PSM 11 ("sparse text, no particular order").
- Near-blank / non-text (extremely low density and region count) → short-circuit path, skip to the existing empty/low-text handling without spending a Tesseract call on a strategy decision (see Edge Cases).

Each classification also carries a **boundary-confidence** signal: how close the feature values were to a bucket boundary (e.g., column-gap strength just above/below the column-detection threshold). This is distinct from OCR confidence and is used only to choose the fallback strategy on a second pass, not to choose the first pass.

**Reworked control flow in `run_ocr_detailed`:**

1. Preprocess image (unchanged).
2. Classify → get `{psm, image_variant, boundary_confidence}`.
3. Run Tesseract pass 1 with the selected `psm` against the selected `image_variant` (still `--oem 3 -l eng+msa`, unchanged).
4. Compute calibrated confidence (unchanged sigmoid calibration) and the new composite score (see Decision Logic).
5. If composite score clears the "good enough" bar, or the internal time budget is already exhausted, return pass 1's result — same safety valve as today.
6. Otherwise run Tesseract pass 2 with a fallback strategy chosen from `boundary_confidence` (alternate PSM on the same image if the classification itself was ambiguous; binarized image at the same PSM if the classification was confident but the OCR result was still poor).
7. Compute pass 2's composite score. Keep whichever of pass 1 / pass 2 scored higher — generalizing today's "keep retry only if confidence improved" to score-based comparison.

**New component: composite scorer.** A pure function taking an OCR pass's lines/confidence and returning a 0–1 composite score from weighted signals (detailed in Decision Logic). No LLM call involved — all signals are cheap regex/string checks computed server-side, mirroring (not calling into) the keyword/pattern logic that already exists client-side in `lib/domain/logic/receipt_layout_analyzer.dart` and the amount-normalization regex already in `ocr_engine.py`'s `_normalize_ocr_amounts`.

**Batch/relaxed mode:** A budget-mode parameter (`interactive` default, `batch` opt-in via the dev tool) controls two things: whether the internal time-budget guard applies at all (relaxed/disabled in batch mode), and how many candidate passes are allowed (2 in interactive mode per the strategy above; a configurable higher number, e.g. up to 4, in batch mode, trying combinations from the existing 2-variant × up to 3-PSM candidate space rather than every possible combination). Batch mode is only reachable from the dev tool / future background reprocessing paths, never from the synchronous `/ocr` endpoint used at capture time.

**Response contract extension:** `OcrResponse` (and internally `OcrLineResult`, which already tracks per-line confidence but doesn't expose it) gains optional telemetry fields: which strategy/PSM was used, how many passes ran, and the composite score. These are additive — the existing key set (`text, confidence, lines, understanding, understanding_error`) is unchanged, new keys are appended. This intentionally breaks the current response-schema-stability test in `test_main.py`, which must be deliberately updated to the new expected key set (see Implementation Guidance) — it is a designed guardrail catching this exact kind of change, not a bug to route around.

## Decision Logic

- When the classifier's density/region-count features indicate near-blank/non-text input, skip strategy selection entirely and go straight to the existing empty/low-text result path (no wasted Tesseract call).
- When no column signal is detected and text density is in the normal range, use PSM 6 against the standard image (today's default behavior, unchanged) for pass 1.
- When a sustained vertical projection-profile gap splits the image width, classify as multi-column and use PSM 4 against the standard image for pass 1.
- When text density and region count are both low but the image isn't near-blank, classify as sparse and use PSM 11 against the standard image for pass 1.
- After pass 1, compute the composite score. If the composite score is at or above the "good enough" threshold, OR the elapsed time already meets/exceeds the internal time budget, return pass 1's result immediately — do not run pass 2. (This generalizes today's confidence-only ≥0.4-skip-retry logic to the new composite score, while preserving the exact same time-budget safety valve from the 2026-07-22 ADR.)
- If pass 2 is warranted and the classifier's boundary-confidence for pass 1 was low (feature values were near a bucket boundary), pass 2 uses the *alternate* PSM (the other layout candidate the classifier was torn between) against the *same, non-binarized* image — because the likely failure mode is segmentation mismatch, not image quality.
- If pass 2 is warranted and the classifier's boundary-confidence for pass 1 was high (a clear bucket match), pass 2 keeps the *same* PSM but switches to the binarized (`shadow_binarize`) image — because the likely failure mode is image quality, which is exactly today's existing fallback behavior, preserved for this case.
- After pass 2, compare composite scores (not raw/calibrated confidence alone) between pass 1 and pass 2, and keep the higher-scoring result. Discard the lower-scoring one even if its raw confidence happened to be higher (this is the fix for the "binarization inflates confidence but produces garbage" failure mode named in the Problem Statement).
- In batch mode, repeat the same per-pass decision logic across up to the configured max passes (higher than 2), trying additional PSM/variant combinations from the existing candidate space when earlier passes don't clear the "good enough" score threshold, and without the interactive path's time-budget cutoff.
- The "good enough" composite-score threshold, and the score component weights, start at documented but explicitly provisional defaults (see Performance Considerations / Testing Strategy) — they are not derived from data yet and must be tuned via the batch-mode dataset evaluation before the feature's default-on rollout.

**Composite score components** (all cheap, computed without an LLM call):

- Calibrated OCR confidence (existing sigmoid-calibrated value) — largest single weight, since it remains a genuine (if imperfect) signal.
- Amount-detection success: does the candidate's text match the existing `RM<amount>`-style pattern used by `_normalize_ocr_amounts`? Binary signal, meaningfully weighted — sparse-but-correct receipts (e.g. a cropped total or bank slip) should not be penalized just because they lack other signals.
- Keyword presence: count of matches against a small static receipt-keyword list (TOTAL, SUBTOTAL, TAX, CASH, CHANGE, GST/SST, RECEIPT, INVOICE, THANK YOU, RM), mirroring (as a lightweight, explicitly-duplicated list — see Implementation Guidance risk) the keyword approach already used client-side in `receipt_layout_analyzer.dart`.
- Text coherence: proxy signal — fraction of recognized tokens that look like plausible words/amounts (alnum-dominant, not excessive symbol noise) versus total tokens.
- Line count sanity: too few lines relative to image size suggests a failed pass; an implausibly high line count relative to image size suggests over-segmentation/noise.
- Merchant-extraction-quality proxy (heuristic only, not real extraction): presence of at least one alphabetic-heavy, plausible-header-like line in the first few recognized lines — approximate, explicitly not equivalent to the client's or the LLM's actual merchant extraction.

## Edge Cases

- **Very blurry image:** classifier's density/region-count features are noisy but still computable (no crash); coherence and amount-detection scoring signals will likely be low across both passes, so the composite score naturally stays low and the existing `needs_review` path is reached — no new failure mode, just a more informative one.
- **Empty OCR output:** classifier flags near-blank/non-text pre-OCR and short-circuits to the existing empty-result path (unchanged), avoiding a wasted strategy decision and a wasted Tesseract call.
- **Receipt with only numbers (e.g. cropped total, bank slip):** amount-detection is the dominant positive scoring signal; scoring must not hard-gate on keyword presence, since a legitimately sparse-but-correct result would otherwise be undervalued.
- **Very long receipt:** classifier and scoring operations must stay bounded — they run on the same already-upscaled (`MIN_OCR_WIDTH`-capped) image as Tesseract itself, using vectorized OpenCV calls; needs an explicit perf test against a long-receipt fixture (see Testing Strategy), since projection-profile and connected-component costs scale with image size.
- **Receipt in an unsupported language:** out of scope (Non-Goals) — `TESSERACT_LANG` stays fixed. The classifier isn't a language detector; a non-Latin-script receipt will still classify on layout signals and likely still score low post-OCR, same net outcome as today, not worse.
- **Screenshot instead of camera photo:** classifier is density/layout-based, not photo-specific, so it degrades gracefully; the existing gated perspective/deskew steps already no-op safely on non-distorted input, and this feature doesn't change that behavior — should be covered by a regression test to confirm no interaction effect.
- **Non-receipt image (wrong image shared):** near-zero text density and region count route it into the near-blank/non-text short-circuit, returning quickly instead of spending a full 2-pass budget on clearly non-receipt input — a genuine latency win from this feature, not just a neutral edge case.
- **Classifier itself errors on malformed/degenerate input** (e.g. a 1-pixel-tall image slipping past upstream validation): must fail safe to the current default strategy (PSM 6, standard image) rather than raising, so a classifier bug can't take down the whole `/ocr` endpoint — mirrors the fail-safe-to-null pattern already established by `receipt_layout_analyzer.dart` (`analyzeReceiptLayout` returns `null` rather than throwing when its own preconditions aren't met).

## Performance Considerations

- **Classifier latency budget:** must be cheap relative to a Tesseract call (which can itself take multiple seconds on a large image) — target well under ~300ms using vectorized OpenCV operations exclusively; no per-pixel Python loops. This number is a design target, not yet measured — must be confirmed with a dedicated timing test (see Testing Strategy).
- **Worst-case interactive latency:** unchanged in shape from today — still at most 2 sequential Tesseract calls plus one small constant classifier overhead. Must not regress the existing time-budget guard's behavior; the two existing budget-guard tests (`skips_retry_when_plain_pass_is_already_slow`, `still_retries_when_plain_pass_is_fast`) must continue passing unmodified.
- **Known external constraint requiring verification before tuning:** `docs/system/architecture.md` documents the production `ocr-proxy` Edge Function's `AbortController` timeout as ~8s, while the OCR engine's own internal retry-budget check allows up to 20s of elapsed time before skipping a retry. These two numbers are in tension — a 20s-eligible retry could already exceed an 8s external timeout today, independent of this feature. **Assumption flagged explicitly**: this spec does not attempt to resolve that pre-existing discrepancy; the implementing agent should re-verify the actual current proxy timeout value before finalizing the interactive budget, since incorrect tuning here would be inherited, not introduced, by this feature.
- **Caching:** not applicable — each receipt image is unique, no repeated-input case to cache against (explicit Non-Goal).
- **Server resource usage:** adds CPU cost (OpenCV feature extraction) but no new memory-heavy or persistent state; stays within the existing single-process-per-request synchronous model. Batch mode's heavier multi-pass trials run entirely off the production request path (dev tool / future background job), so they don't add load to interactive-path resource usage.
- **Batch mode cost:** explicitly allowed to be slower/heavier per receipt, since it's the tuning/evaluation harness, not a production latency path.

## Security Considerations

No new attack surface: same single image-upload boundary as today, no new external calls, no new persistent data. The only new consideration is validating any new adaptive-strategy environment variables (e.g. score-weight overrides, "good enough" threshold, batch-mode pass cap) defensively — malformed values should fail safe to the documented defaults rather than crashing the service, consistent with how existing `PREPROCESS_*` env vars should already be handled (verify the existing validation pattern during implementation and follow it, rather than inventing a new one).

## Tradeoffs

- **Heuristic decision table vs. ML classifier.** Chosen: heuristic. An ML model would need labeled training data this project doesn't have, and adds a model-serving dependency to a currently dependency-light service. This also matches the precedent already set client-side: `receipt_layout_analyzer.dart` explicitly rejected an ML layout model in favor of geometric heuristics.
- **Always try 3–4 passes vs. capped at 2 on the interactive path.** Chosen: capped at 2 (per explicit user decision). Unrestricted multi-pass reopens exactly the latency risk the 2026-07-22 ADR closed after the documented 122s incident, and risks exceeding the ~8s external proxy timeout on the interactive path. The relaxed batch mode absorbs the "try more things" use case without that risk.
- **Classifying receipt semantic type (restaurant/supermarket/bank) vs. classifying visual layout characteristics.** Chosen: visual/layout only. Semantic type isn't knowable before OCR text exists — attempting it pre-OCR would require either guessing from raw pixels (unreliable) or running OCR first (defeating the purpose of pre-OCR strategy selection). This reframes the original request's example ("restaurant vs. supermarket") onto what's actually measurable at the right point in the pipeline.
- **Per-pass LLM-based merchant-quality scoring vs. cheap heuristic proxy.** Chosen: heuristic proxy, LLM called once total (unchanged from today). Scoring every candidate pass through the LLM would multiply an already 25s-budget call by the number of passes, directly contradicting the 2026-07-23 LLM-cleanup ADR's "extends the existing single call, no second round trip" principle.
- **New third preprocessing variant (e.g. "enhanced contrast") vs. reusing only the two existing variants.** Chosen: reuse only. Consistent with this codebase's established "measure before adding a variant" culture (the PaddleOCR-era lesson that unconditional CLAHE/pre-binarization can measurably hurt Tesseract, documented in `memory/experiments.md`) — a new variant should be proposed only once the two-variant system's dataset evaluation shows a specific gap neither existing variant covers.

## Implementation Guidance

Suggested order of work:

1. **Classifier module.** Add a new pure-function module (e.g. `services/ocr-api/ocr_api/receipt_classifier.py`) taking the preprocessed grayscale image and returning the feature set + strategy bucket + boundary-confidence. Build and unit-test this in isolation first — it has no dependency on Tesseract or the rest of the pipeline. Inspect `preprocessing.py` to confirm exactly which image object is available at the hook point (post-CLAHE/illumination, pre-Tesseract) and its dtype/shape conventions.
2. **Strategy decision table.** A small pure function/dict mapping classifier buckets to `{psm, image_variant}`. Inspect `ocr_engine.py`'s current `_config()` to generalize it from "PSM sourced only from `TESSERACT_PSM` env var" to "PSM sourced per-call from the selected strategy, with the env var becoming the fallback default when adaptive mode is off."
3. **Composite scorer.** Reuse the existing amount-detection regex already in `_normalize_ocr_amounts` rather than rewriting it. Port a keyword list mirroring (not calling into) `receipt_layout_analyzer.dart`'s keyword hints for the server-side language. **Flag explicitly**: this creates a second, Python-side copy of a keyword list that already exists in Dart — acceptable duplication (small, low-churn list) unlike the layout-analysis logic itself (which the 2026-07-23 ADR deliberately kept client-side only), but worth a code comment noting the duplication so a future keyword addition doesn't get made in only one place.
4. **Rework `run_ocr_detailed`'s control flow** per Decision Logic — classification-informed pass 1, boundary-confidence-informed pass 2 fallback choice, composite-score-based keep decision. Preserve the existing time-budget guard exactly; the two existing budget-guard tests must keep passing unmodified.
5. **Batch-mode budget parameter.** Inspect `bin/process_receipts.dart` and `scripts/process_receipts.ps1` to see how they currently invoke the OCR engine/API, and wire through a batch-mode flag that relaxes the time budget and raises the pass cap.
6. **Extend `models.py`** with additive optional telemetry fields (strategy/PSM used, pass count, composite score) on `OcrResponse`/internal structures. Update the response-schema-stability test in `test_main.py` deliberately to the new expected superset key set — this test is designed to catch exactly this kind of change; updating it is the intended outcome, not a workaround.
7. **Feature flag + shadow mode.** Add `ADAPTIVE_OCR_ENABLED` (default off), matching the existing `PREPROCESS_*`/`LLM_CLEANUP_ENABLED` opt-in convention. Initial rollout should log the classifier's decision and resulting score alongside the still-active legacy fixed-PSM6 path's output, without changing what's returned, to gather real data before flipping the default (see Rollout Plan).

Files to inspect before starting: `services/ocr-api/ocr_api/ocr_engine.py`, `services/ocr-api/ocr_api/preprocessing.py`, `services/ocr-api/ocr_api/models.py`, `services/ocr-api/ocr_api/main.py`, `services/ocr-api/tests/test_ocr_engine.py` and its `conftest.py` fixtures (existing test/fixture conventions to follow), `docs/plans/2026-07-21-ocr-preprocessing-pipeline-upgrade.md` and its 2026-07-22/23 siblings (env-var and threshold naming conventions to match), `lib/domain/logic/receipt_layout_analyzer.dart` (heuristic/fail-safe style precedent and keyword-list content to mirror), `bin/process_receipts.dart` / `scripts/process_receipts.ps1` (batch-mode wiring point).

Risks to watch: keyword-list drift between the Dart and Python copies over time; the unresolved 8s-proxy-vs-20s-internal-budget discrepancy noted in Performance Considerations, which predates this feature but interacts with it; unvalidated scoring weights being mistaken for final tuned values before the dataset evaluation runs; the response-schema-stability test failing on this change is expected and must be updated deliberately, not bypassed.

## Testing Strategy

- **Classifier unit tests:** fixture images with known characteristics (multi-column, dense single-column, sparse, near-blank/non-text) asserting correct bucket selection, following the existing fixture pattern in `test_ocr_engine.py`/`conftest.py` (e.g. alongside `skewed_low_contrast_image_bytes`).
- **Strategy table unit tests:** exhaustive table-driven tests over all bucket → strategy mappings (it's a small pure function, cheap to cover completely).
- **Composite scorer unit tests:** fixed OCR line/confidence fixtures asserting each score component and the total; include a dedicated regression test for the "binarization raises raw confidence but produces incoherent text" scenario named in the Problem Statement, proving the new scorer catches what confidence-only comparison couldn't.
- **Integration tests:** extend the existing retry-trigger tests in `test_ocr_engine.py` to cover both new pass-2 fallback paths (alternate-PSM vs. binarize) instead of the current always-binarize path; the two existing time-budget tests must keep passing unmodified.
- **Schema regression test:** update the response-schema-stability test to the new backward-compatible superset key set, plus an explicit test that a client reading only the old key set is unaffected by the new optional fields.
- **Latency/perf test:** benchmark classifier overhead on a large/long-receipt fixture and assert it against the target budget defined in Performance Considerations (target ~300ms, to be confirmed by real measurement, not assumed).
- **Dataset evaluation via the batch tool:** run the legacy fixed-pipeline and the new adaptive pipeline over the same labeled folder of representative receipt images (varied formats matching the existing `receipt_type` field: retail, restaurant, bank/wallet, etc.) and compare aggregate amount-detection rate, confidence distribution, and latency. This is the gate for tuning the decision table and score weights, and for the shadow-mode-to-default-on rollout decision.
- **Full regression:** existing `test_ocr_engine.py`/`test_main.py` suites must pass unmodified except for the deliberately-updated schema-stability test.

## Rollout Plan

1. Ship behind `ADAPTIVE_OCR_ENABLED` (default off), matching the existing opt-in-flag convention in this service.
2. Shadow mode first: run classification + scoring and log the outcome alongside the still-authoritative legacy fixed-PSM6 pipeline's result, without changing what's returned to callers. Use this window (plus the batch tool's dataset evaluation) to gather real accuracy/latency data.
3. Tune the decision table and score weights against that data before considering default-on.
4. Flip the default on once the dataset evaluation shows a measurable accuracy improvement with latency confirmed inside the existing budget; keep the flag as a rollback lever.
5. Backward compatibility during the transition: new response fields are additive/optional throughout, so client behavior is unaffected regardless of flag state — no coordinated client release is required to ship or to roll back this feature.
