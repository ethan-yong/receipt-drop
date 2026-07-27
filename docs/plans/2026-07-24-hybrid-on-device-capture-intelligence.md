# Feature: Hybrid On-Device Capture Intelligence

## Overview

A lightweight on-device analysis layer that scores a receipt photo's usability — blur, lighting, and framing/geometry — before it is handed to the existing OCR pipeline. It runs in two places: a throttled live pass during capture that drives real-time camera guidance ("hold steady", "move closer"), and a one-shot full-resolution pass on the final image (from either the live camera or gallery/file picking) immediately before upload. Poor scans get an in-app retake suggestion instead of only being discovered after a round trip to `services/ocr-api`.

## Problem Statement

Today, image-quality problems surface only after the full pipeline runs: `ReceiptIngestService` persists the file, uploads it to `services/ocr-api` (or via `ocr-proxy`), and only then does a bad scan show up — either as a low `ocr_service_confidence`/`ocr_confidence` result routed to the review queue, or as an outright OCR failure. `ReceiptScanProcessingScreen`'s existing `_failedOverlay()` (`lib/features/share/receipt_scan_processing_screen.dart:694-759`) already assumes "too blurry" is the likely cause of failure — it hardcodes that message for *any* processing failure — which is itself evidence the product already expects blur/quality to be the dominant failure mode, but has no way to detect it before the network round trip. Every rejected-after-the-fact image has already: consumed a Tesseract pass (and possibly the confidence-gated binarize retry, per `docs/plans/2026-07-21-ocr-preprocessing-pipeline-upgrade.md`), consumed an LLM understanding call, and cost the user a full upload-and-wait cycle before they learn they need to retake the photo.

## Goals

- Detect blur, poor lighting (too dark, overexposed, glare), and framing/geometry problems (receipt absent, too small in frame, likely cropped) on-device, before upload.
- Give real-time guidance during live capture, and a final pass-or-flag check at the moment of capture/selection, regardless of entry point (live camera, gallery, file picker).
- Reduce wasted uploads and server-side OCR/LLM work on images that were never going to parse well.
- Never block or lose a receipt outright — flagged images can still be saved, consistent with this codebase's existing "never silently drop a receipt" principle.

## Non-Goals

- **No on-device OCR.** This does not read text or route through any recognition model. `memory/experiments.md` already documents that on-device OCR (Google ML Kit) was tried and deliberately abandoned in favor of the self-hosted Tesseract service, for cross-device consistency and testability (`bin/process_receipts.dart` running the same engine as production). This feature does not revisit that decision — it never extracts text, only scores the pixels.
- **No client-side image correction.** No perspective warp, deskew, cropping, or contrast enhancement is performed or shipped to the server. `services/ocr-api/ocr_api/preprocessing.py` already owns document detection, deskew, upscaling, and gated CLAHE (`docs/plans/2026-07-21-ocr-preprocessing-pipeline-upgrade.md`) — this feature is diagnostic only (score + reject/warn), never corrective, to avoid a second, divergent copy of image-correction logic.
- **No bundled ML model.** Per the architecture decision below, all analysis is traditional CV heuristics — no TFLite model, no model asset, no inference runtime.
- **No new server-side telemetry schema.** This spec does not add a Postgres column, sync field, or analytics event for the on-device quality score. Whether/how to log outcomes for the metrics in Testing Strategy is left as an explicit open question (see Testing Strategy), not something to build speculatively here.
- **No change to the existing post-upload pipeline.** `ocr_service_confidence`, `ocr_confidence`, `needs_review` routing, and enrichment are all untouched. This on-device score is a distinct, earlier, client-only signal — it must never be conflated with `ocr_confidence` (amount-extraction confidence) or `ocr_service_confidence` (OCR scan-quality confidence), the same two fields a past bug already conflated (`.claude/context.md`).
- **Desktop and web behavior is out of scope for live guidance** (see Implementation Guidance's open risk note) — both keep today's gallery/file-picker-only capture path at minimum for this feature's first version.

## Proposed Solution

Add a new pure-Dart analyzer (`CaptureQualityAnalyzer`) that takes a decoded image buffer and returns a verdict (`good` / `marginal` / `reject`) plus the specific issue(s) found. This analyzer is the single source of truth for "is this photo usable" and is called from two places: a throttled ~2-3 fps loop over downsampled live-camera frames (driving an on-screen guidance overlay before the shutter is pressed), and once at full resolution on the final image — whether it came from the live camera, the gallery, or the file picker — immediately before `ReceiptIngestService.ingestBytes`/`ingestPath` is called. A `reject`/severe-`marginal` verdict at the final-image stage shows a lightweight "Retake or use anyway?" prompt; nothing is ever hard-blocked. Live capture replaces `image_picker`'s camera source with a custom preview screen built on the `camera` plugin (new dependency); gallery and file-picker paths are unchanged except for gaining the same one-shot final check.

## User Experience

**Live camera flow (new):**
1. User taps Camera in `ReceiptCaptureMenu` → new `ReceiptCameraScreen` opens (replaces today's `ImagePicker(source: ImageSource.camera)` hand-off to the OS camera app).
2. While framing the shot, a throttled analysis loop scores downsampled preview frames. A short guidance string appears when a verdict is `marginal`/`reject` ("Move closer", "Reduce glare", "Hold steady", "Capture entire receipt"); the shutter button always stays enabled and tappable — the live pass only changes overlay text/color, it never disables capture.
3. User taps the shutter at any time — a `good` live verdict is a signal, not a gate.
4. Full-resolution captured image is immediately re-analyzed once (a fresh check, since resolution changes blur/frame-fill numbers — see Technical Design).
5. **Verdict `good`:** proceeds straight into the existing `ReceiptScanProcessingScreen` flow, unchanged.
6. **Verdict `marginal`/`reject`:** a brief inline prompt shows the specific issue ("This looks blurry") with two actions: **Retake** (returns to the live preview) and **Use anyway** (proceeds as normal). No forced retake, no dead end.

**Gallery / file-picker flow (unchanged entry, new final check):**
1. User picks an image exactly as today.
2. Before `ReceiptIngestService` is called, the same one-shot full-resolution analysis runs.
3. Same `good` → proceed / `marginal`,`reject` → Retake-or-Use-anyway prompt as above. "Retake" here re-opens the picker/camera menu rather than a live preview.

**Failure-message consistency:** `ReceiptScanProcessingScreen`'s `_failedOverlay()` currently shows a hardcoded "too blurry" message for every processing failure. Once a real capture-quality reason is available from this feature, that screen should surface the *actual* reason if the image was flagged pre-upload (still generic-blur wording only for genuine post-upload OCR failures where no on-device flag exists) — a UX consistency fix worth doing alongside this feature, not a separate one.

**Offline behavior:** identical experience with or without connectivity — all analysis is on-device, no network dependency, consistent with the app's local-first design.

## System Impact

- **Client application (`lib/`)**: primary surface. New pure-logic module (`lib/domain/logic/`), new capture screen and guidance overlay widget (`lib/features/share/`), changes to `ReceiptCaptureFlow`/`ReceiptCaptureMenu` entry points, and a messaging tweak to `ReceiptScanProcessingScreen`. New dependencies in `pubspec.yaml` (`camera`, and an image-decoding/pixel-buffer package — see Model Considerations).
- **Backend services (`services/ocr-api`, `services/leaderboard-api`)**: not affected. No new endpoints, no changed contracts.
- **Database/storage**: not affected — no new Postgres columns, no new Drift tables/columns. (See Non-Goals on telemetry.)
- **AI/ML pipeline**: not affected — `services/ocr-api`'s Tesseract and LLM-understanding steps are unchanged; this feature deliberately introduces no ML of its own.
- **Infrastructure**: none server-side. Client app size increases modestly from the two new dependencies.
- **External integrations**: none.

## Technical Design

**Major components:**

1. **`CaptureQualityAnalyzer`** (new, `lib/domain/logic/capture_quality_analyzer.dart`) — pure, platform-agnostic functions operating on an already-decoded pixel buffer. Modeled on the existing `receipt_layout_analyzer.dart`'s shape (pure logic, no I/O, unit-testable). Three independent scoring functions feed one combined verdict:
   - Blur: a variance-of-Laplacian-style edge-response metric on a downsampled grayscale copy — low variance indicates blur.
   - Lighting: grayscale histogram mean and clipping ratios (fraction of near-black / near-white pixels) — flags too-dark, overexposed, or low-dynamic-range (flat/glare-washed) frames.
   - Geometry/framing: edge-density and bounding-box fill-ratio estimate — flags "no receipt-like content detected", "too small in frame", or "likely cropped at the edges".
   - These combine into a single `CaptureQualityResult`: an overall verdict (`good`/`marginal`/`reject`) plus the list of specific issues found, each carrying enough detail to pick a guidance string.

2. **`ReceiptCameraScreen`** (new, `lib/features/share/`) — wraps the `camera` plugin's controller, replacing `image_picker`'s camera source as the entry point from `ReceiptCaptureMenu`'s `onCamera` callback. Owns the frame-sampling throttle and the shutter action.

3. **Guidance overlay widget** (new, `lib/features/share/`) — pure presentational widget mapping a `CaptureQualityResult` to a short instruction string and a debounced/hysteresis-smoothed visual state (so guidance text doesn't flicker between frames). Testable independent of any real camera by feeding it synthetic results directly.

4. **Post-capture gate** — a small coordinating function called from both `ReceiptCameraScreen` (after shutter tap) and the existing gallery/file-picker paths in `ReceiptCaptureFlow` (`lib/features/share/receipt_capture_flow.dart:38-71`), before `ReceiptIngestService.ingestBytes`/`ingestPath` is invoked. Runs `CaptureQualityAnalyzer` once at full resolution and, on `marginal`/`reject`, shows the Retake-or-Use-anyway prompt described in User Experience.

5. **Platform split**: `CaptureQualityAnalyzer` itself is pure Dart and needs no split. `ReceiptCameraScreen` (live guidance) is native-only for this version — web and desktop continue using the existing gallery/file-picker entry points with only the post-capture gate applied, following the same `foo.dart`/`foo_io.dart`/`foo_web.dart` conditional-export convention used everywhere else in this codebase (`docs/system/architecture.md`'s "Platform-split pattern" section) if any camera-plugin-specific code needs isolating from web/desktop builds.

**Data flow (live path):** camera frame stream → throttle to ~1 sampled frame per 300-500ms → downsample to a small buffer (e.g. longest edge ~240-320px) → `CaptureQualityAnalyzer.analyze()` → `CaptureQualityResult` → guidance overlay text update. On shutter tap: full-resolution JPEG captured → `CaptureQualityAnalyzer.analyze()` run again at full resolution (a separate call — see architectural decision below) → verdict → proceed or show Retake/Use-anyway → existing `ReceiptIngestService` flow, unchanged from that point on.

**Data flow (gallery/file path):** picked image bytes → decode → `CaptureQualityAnalyzer.analyze()` at full resolution → verdict → proceed or show Retake/Use-anyway → existing flow.

**Architectural decisions that matter:**

- **Two-tier analysis, not one.** The live pass runs throttled and on a downsampled buffer purely to drive guidance text cheaply; the actual accept/reject decision is always made once, at full resolution, at the moment of capture or selection. These are two separate calls to the same analyzer, not one shared result — resolution changes what "blurry" or "cropped" numerically means, so live-preview-resolution scores and full-resolution scores are not interchangeable and must be tuned/thresholded independently.
- **One analyzer, two call sites.** `CaptureQualityAnalyzer` has no knowledge of the camera plugin or of `image_picker` — it only consumes a decoded buffer. This keeps it unit-testable in isolation and guarantees the live-camera path and the gallery/file-picker path enforce identical rules, rather than drifting into two different quality bars.
- **Diagnostic only, never corrective.** The analyzer never modifies the image. All actual pixel correction (deskew, perspective warp, contrast) stays exclusively in `services/ocr-api/ocr_api/preprocessing.py`, preserving a single source of truth for image correction and avoiding a second, client-side copy that could drift out of sync with server-side tuning.

## Decision Logic

- If blur score falls below a reject-tier threshold → issue `blurry`; guidance text "Hold steady". (Exact threshold: **TBD, needs tuning** — see Implementation Guidance.)
- If blur score is below a warn-tier threshold but above the reject-tier one → issue `blurry`, verdict `marginal` only.
- If grayscale histogram mean is below a dark threshold → issue `too_dark`; guidance "Move to better light" (or "Turn on flash" if the device has one and it's currently off).
- If bright-pixel clipping ratio exceeds an overexposure threshold → issue `glare_or_overexposed`; guidance "Reduce glare" / "Avoid reflections".
- Lighting checks run and are evaluated **before** the blur score is trusted: a near-black frame produces meaningless edge-response values (no edges to blur), so if the lighting check already flags `too_dark`, the blur result for that frame is not additionally surfaced — only the lighting issue is shown, to avoid a confusing double message.
- If frame fill-ratio (receipt-like content vs. background) is below a "too small" threshold → issue `too_small_in_frame`; guidance "Move closer" / "Capture entire receipt".
- If fill-ratio is above a "likely cropped" threshold (receipt content touches the frame edges on multiple sides) → issue `likely_cropped`; guidance "Capture entire receipt" (back away slightly).
- If edge density across the whole frame is very low (no plausible rectangular high-contrast region at all) → issue `no_receipt_detected`. This is a `reject`-tier signal, but per the enforcement policy below it is still overridable, not a hard stop.
- If more than one distinct high-edge-density region is detected with no single dominant region → treat as ambiguous, not a hard rejection: surface a generic "Make sure only one receipt is in frame" hint at `marginal` tier only. Reliable multi-receipt detection is out of reach for these heuristics — the design deliberately avoids overclaiming precision here.
- When multiple issues fire simultaneously, surface only the single highest-priority one (avoid multi-line guidance text): proposed priority order is `no_receipt_detected` > lighting issues (`too_dark`/`glare_or_overexposed`) > `blurry` > geometry issues (`too_small_in_frame`/`likely_cropped`/ambiguous-multi-region). This ordering is a starting point for tuning, not a fixed law — validate against real captures.
- **Verdict tiers → enforcement:** `good` (no issues) → proceeds silently, no prompt at all. `marginal` (a single non-severe issue, or an ambiguous geometry case) → the live overlay shows a hint but the shutter stays fully enabled throughout; at the post-capture gate, a lightweight, dismissible prompt offers Retake or Use-anyway. `reject` (a severe issue — deep-blur floor, `no_receipt_detected`, or extreme exposure clipping) → same Retake-or-Use-anyway prompt but visually more emphatic; **still never hard-blocking** — per the chosen soft-warn policy, "Use anyway" is always present and always works, consistent with this codebase's documented "confidence scores tune the parser, not the user's mood" principle and its existing review-queue safety net for anything that slips through.
- **Live-pass performance fallback:** if the device can't sustain even the throttled ~2-3 fps sampling rate (measured from the actual processing duration of the first several frames after camera init, not a hardcoded device-model list), the live overlay is disabled entirely for that session — no guidance text is shown — while the shutter and the mandatory post-capture full-resolution check continue to work normally. Degrading to a lower live frame rate instead of disabling was considered and rejected: below a certain rate, guidance text becomes stale/misleading rather than merely infrequent.
- Corrupted or undecodable image bytes at any analysis point → analyzer fails closed: skip analysis, treat as verdict `good` (i.e., proceed to upload unimpeded). This is a diagnostic feature, not a validation gate — it must never be able to block a receipt outright due to its own internal failure.

## Edge Cases

- **Old/low-end device can't sustain live sampling** — falls back to overlay-disabled, post-capture-check-only mode per the Decision Logic fallback above; never freezes or visibly stutters the camera preview itself.
- **Near-black frame** — lighting check must run and short-circuit before the blur result is surfaced, or a pitch-black photo could otherwise show a confusing "blurry" message when the real problem is darkness (see Decision Logic).
- **Long or unusually shaped receipts** (thermal paper, folded/crumpled) — the "roughly rectangular" fill-ratio assumption will likely misfire on legitimate long/narrow receipts. Geometry issues are capped at `marginal` tier, never the sole cause of a `reject` verdict, specifically to avoid hard-discouraging valid odd-shaped receipts.
- **Multiple receipts in one frame** — ambiguous by design (see Decision Logic); surfaced as a non-blocking generic hint only, never a reject.
- **Screenshot of a digital/e-receipt** — often scores fine on blur/lighting (screenshots are typically crisp) but fails geometry (no receipt-shaped edges against a uniform background). Flagged `marginal` at most — screenshots are a legitimate real input the existing OCR/parse pipeline already handles, so this must not become a hard block.
- **App backgrounded mid-live-preview** (incoming call, notification) — the camera controller must be paused/disposed on a lifecycle change (`WidgetsBindingObserver`) and cleanly reinitialized on resume, or the camera hardware handle leaks — a well-known `camera` plugin pitfall.
- **Large gallery image (12MP+)** — the analyzer must downsample internally before running any heuristic, regardless of caller; it should never assume the caller has already sized the image down. Same downsample-first rule applies uniformly to both the live-preview tier and the full-resolution post-capture tier.
- **Rapid repeated shutter taps** while the one-shot full-resolution analysis is still running — the shutter must be disabled/debounced for that brief window to avoid triggering two concurrent ingest attempts on the same tap-happy user.
- **Gallery/file-picker image that's actually fine but old/already low quality** — must get exactly the same treatment as a fresh live capture; the two entry points must never diverge in what verdict they'd produce for the same bytes (enforced by both routing through the identical `CaptureQualityAnalyzer` call).

## Performance Considerations

- **Camera latency**: live analysis runs off the raw camera image stream, decoupled from the preview widget's own rendering — it must never add perceptible lag to what the user sees through the viewfinder.
- **CPU usage**: live pass throttled to ~2-3 fps on a downsampled buffer (longest edge ~240-320px) keeps per-frame heuristic cost low; the one full-resolution pass runs exactly once per capture/selection. Concrete latency budgets (e.g. a target ms ceiling for the full-res pass on a mid-range device) are **not yet determined** — this repo has no existing benchmark harness for client-side image processing; establish a budget empirically during implementation rather than guessing a number here.
- **Memory**: never hold more than one full-resolution decoded buffer alive at a time; downsample-then-discard for the live tier, and release the full-resolution buffer immediately after the one-shot analysis call.
- **Battery**: a continuous camera preview with periodic analysis is inherently more battery-intensive than today's instant hand-off to the OS camera app via `image_picker`. This is a direct, accepted cost of choosing live guidance over post-capture-only (see Tradeoffs) — no specific battery budget is defined here; validate empirically on real devices before wide rollout.
- **Offline behavior**: fully on-device, zero network calls — unaffected by connectivity, consistent with the existing local-first design.
- **Network usage / server cost**: expected reduction in uploads and OCR/LLM calls for images that would have failed anyway, but no baseline number exists yet in this codebase to size the expected savings against — see Testing Strategy.

## Security Considerations

- All analysis happens entirely on-device; no image data or analysis result is transmitted anywhere as part of this feature. If anything, it reduces exposure by discouraging uploads of images the user chooses to retake instead.
- No new permission category: the `camera` plugin still triggers the same OS camera permission `image_picker`'s camera source already triggers today — this feature changes *when* the camera UI appears (in-app vs. OS-native), not what permission is requested.
- This is a UX optimization, not a trust/security boundary. A modified client that skips this check entirely just uploads a bad image — exactly what happens today — which the existing server-side pipeline already handles via `pipeline_status='needs_review'`. This feature must never be treated as, or relied upon as, a server-side validation guarantee.

## Tradeoffs

- **Post-capture-only (rejected in favor of live guidance)**: cheaper — no new `camera` dependency, no custom preview screen, no camera-lifecycle edge cases. Rejected because it loses the core UX value being sought here: catching a bad photo *before* the shutter, rather than telling the user after they've already taken it. The live-guidance path pays for that value with the added `camera` dependency, battery cost, and platform-lifecycle complexity called out throughout this document.
- **A bundled ML model (rejected)**: could plausibly score higher raw accuracy, especially on "is this a receipt at all" and precise corner/geometry detection. Rejected for the same reason on-device OCR (Google ML Kit) was already abandoned in this codebase (`memory/experiments.md`): cross-device/OS inconsistency in on-device inference, plus a training-data/model-versioning concern with zero precedent anywhere in this repo (no bundled model assets exist today). Traditional CV heuristics are cheaper to implement, fully deterministic, and tunable with the same batch-fixture workflow already used for the server-side preprocessing plan.
- **Porting the server's real document-corner detector (OpenCV/`cv2`-based) to the client (rejected/deferred)**: `services/ocr-api/preprocessing.py`'s `detect_document_corners()` (Canny + contour + `approxPolyDP`) is more precise than simple edge-density heuristics, but there is no equivalent lightweight OpenCV binding readily available in this Flutter app today, and porting a Canny/contour pipeline to pure Dart is a much heavier lift than this feature needs — it only requires a coarse go/no-go signal, not a precise perspective transform (that stays server-side, per Non-Goals).
- **Hard-block vs. soft-warn (soft-warn chosen, per explicit product decision)**: a hard block would more aggressively prevent bad uploads, but risks recreating exactly the "anxiety UI"/receipt-loss failure mode this codebase's design principles explicitly warn against (`docs/system/architecture.md`'s "Design patterns worth knowing" section). Soft-warn accepts some "wasted" uploads from users who override anyway, in exchange for preserving that principle — the existing review queue is already the accepted final safety net for exactly this kind of edge case.

## Implementation Guidance

Suggested order of work:

1. **Build `CaptureQualityAnalyzer` first, as pure Dart, fully decoupled from any camera or picker code.** Add unit tests in `test/` against synthetic fixtures (sharp/blurred pairs, dark/bright/normal-exposure triples, full-frame/cropped/multi-region framing variants) — mirror how `services/ocr-api/tests/conftest.py` builds its own synthetic low-contrast/rotated fixture. This is the correctness-critical, CI-testable part; get it right and tunable before any UI work begins.
2. **Wire the analyzer into the post-capture-only path next** — the gallery and file-picker flows in `ReceiptCaptureFlow` (`lib/features/share/receipt_capture_flow.dart`), before `ReceiptIngestService.ingestBytes`/`ingestPath` is called. This alone delivers most of the stated goals (catch bad scans earlier, reduce wasted server work) with no new dependency and no camera-lifecycle risk — validate it in isolation before adding live guidance.
3. **Add the `camera` plugin dependency and build `ReceiptCameraScreen`** as a distinct, later phase — new dependency, new platform-lifecycle surface, and real per-device performance variance that steps 1-2 don't have. Build it against the already-proven analyzer from step 1, not in parallel with it.
4. **Handle camera lifecycle carefully** (`WidgetsBindingObserver`, pause/dispose/resume) — this is the most common source of bugs in Flutter apps using the `camera` plugin generally, independent of this feature's own logic.
5. **Tune all thresholds using the existing `bin/process_receipts.dart` / `scripts/process_receipts.ps1` batch tool** against a folder of real receipt photos (including deliberately bad ones) — the same tuning workflow already established for `docs/plans/2026-07-21-ocr-preprocessing-pipeline-upgrade.md`'s server-side thresholds.

Areas to inspect first:
- `lib/features/share/receipt_capture_flow.dart` and `receipt_capture_menu.dart` — the entry points that need to change.
- `lib/features/share/receipt_ingest_service.dart` / `receipt_ingest_service_io.dart` — exactly where the post-capture gate needs to hook in, before `persistReceiptBytes`.
- `lib/features/share/receipt_scan_processing_screen.dart:694-759` (`_failedOverlay`) — currently hardcodes a generic "too blurry" message for every failure; worth threading the real capture-quality reason through here as a related fix.
- `lib/domain/logic/receipt_layout_analyzer.dart` — an existing, analogous pure-logic module (OCR-side layout/zone scoring) worth modeling `CaptureQualityAnalyzer`'s shape and test style after.

Potential risks / open questions:
- **Desktop camera support is genuinely weaker in the Flutter `camera` plugin ecosystem than mobile.** This project targets Android/iOS/Web/Desktop from one codebase (`CLAUDE.md`). This spec assumes live guidance ships mobile-first, with web and desktop continuing to use gallery/file-picker entry points (still gaining the post-capture check) for this version — flagging this explicitly as an assumption, since it wasn't settled by product input and affects the platform-split file structure.
- All numeric thresholds throughout this document are placeholders pending real tuning — do not hardcode guessed constants as if they were final; follow the batch-tool tuning step before shipping to real users.

## Testing Strategy

- **Functional unit tests**: `CaptureQualityAnalyzer`'s blur/lighting/geometry scoring functions, against synthetic fixtures generated the same way as `services/ocr-api/tests/conftest.py` (sharp vs. blurred, dark/bright/normal exposure, full-frame/cropped/multi-region framing). Live in `test/`, alongside this codebase's existing concentration of OCR/parse-pipeline tests (per `CLAUDE.md`'s directory guidance).
- **Edge case tests**: corrupted/undecodable bytes (must fail open, never crash), a near-black synthetic frame (lighting check must short-circuit before blur), an oversized synthetic image (downsample path must engage).
- **Widget tests for the guidance overlay**: feed synthetic `CaptureQualityResult` values directly into the overlay widget to verify text-mapping and debounce/hysteresis behavior, without needing a real camera — decoupling this from the parts of the `camera` plugin that can't be exercised in CI.
- **Manual/device testing**: live preview + guidance overlay must be manually verified on at least one low-end and one modern device per mobile platform (Android/iOS), since real camera behavior and per-device performance variance aren't reproducible in CI.
- **Capture-success-rate / OCR-failure-reduction metric**: no existing baseline exists for "% of captures that fail OCR" in this codebase today. Recommend establishing one using the existing `pipeline_status='needs_review'` rate as a proxy — measured before this feature ships, then again after — rather than inventing new bespoke instrumentation with no baseline to compare against (see Non-Goals on telemetry).
- **User satisfaction metrics**: out of scope for this spec's implementer to instrument speculatively; a product-side follow-up once the feature has shipped and real usage data exists.

## Rollout Plan

- Ship in the same two stages as Implementation Guidance: **(1)** post-capture-only gate first, behind a simple local toggle (e.g. an `AppPrefs`-backed flag or compile-time const, consistent with how the server pipeline gates new behavior via `PREPROCESS_*` env flags) so it can be disabled instantly if thresholds misfire in the field; **(2)** live camera guidance as a separate, later-enabled flag once stage 1's thresholds are validated against real usage.
- Because enforcement is soft-warn-with-override throughout, there is no backward-compatibility hazard: a user on an app version without this feature simply skips the pre-check, exactly like today. No server contract changes, no data migration.
- **Rollback**: flip the feature flag off. The existing capture flow (`image_picker` straight into `ReceiptIngestService`) remains fully intact underneath both stages, so rollback is a flag flip, not a code revert.
- Threshold tuning (via the batch tool, per Implementation Guidance) should happen in a pre-release phase against a curated real-receipt fixture set — including deliberately bad photos — before stage 1 is enabled for any real users.
