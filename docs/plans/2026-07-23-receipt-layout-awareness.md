# Feature: Layout-Aware Receipt Zone Detection

## Overview

A lightweight heuristic layer that classifies OCR output lines into header
(merchant/store info), body (item rows), and footer (totals/payment) zones,
using signals already available or cheaply extractable from the existing
pipeline — line order, bounding-box position, text height, alignment, and the
keyword regexes already used elsewhere in this codebase. Zone membership is fed
into the three existing Dart heuristic functions (`extractMerchantCandidates`,
`extractReceiptLineItems`, `parseRmAmountFromOcr`) as an additional scoring
signal — never a hard filter that could make an already-working extraction fail.

## Problem Statement

OCR text is currently flattened to a newline-joined string before nearly every
heuristic runs. The only spatial signal used anywhere in the pipeline today is
`OcrLine.heightRatio` — added specifically to let `extractMerchantCandidates`
prefer a visually large header/logo line (2026-07-08 decision). There is no
x/y bounding-box data anywhere, despite `ocr_engine.py`'s `_run_tesseract()`
already calling `pytesseract.image_to_data()`, which returns per-word
`left`/`top`/`width` in the same dict `height` is already read from — genuinely
free data that's simply discarded today.

Positional reasoning elsewhere in the pipeline is coarse and line-count-based,
not structure-aware: `merchant_extractor.dart`'s `merchantScanLines = 15` is a
fixed header window regardless of actual receipt length, and
`rm_amount_parser.dart`'s footer heuristic is a flat "bottom 20% of lines"
(`bottomThreshold = (lines.length * 0.8).floor()`) with no real zone boundary.
This produces two concrete, current failure modes: (1) `extractMerchantCandidates`'s
Pass 2 (`_businessWordHints`) can score a menu item as a merchant candidate if a
business word ("kopitiam", "bistro") happens to appear inside an item name within
the first 15 lines — nothing today distinguishes "this line is still in the
header" from "this line is already in the item body"; (2) `extractReceiptLineItems`
only excludes boilerplate/discount/total-keyword lines, not the phone/date/
postcode metadata patterns `merchant_extractor.dart` already regexes for
elsewhere (`_phoneNumberHint`, `_dateHint`, `_postcodeHint`) — a bare-looking
metadata line (e.g. a table number) can slip through the bare-price regex tier
as a false item.

## Goals

- Classify OCR lines into header/body/footer zones using cheap, already-or-
  nearly-available signals: line order, bounding-box position (server-side,
  from data pytesseract already returns), text height ratio, horizontal
  alignment, numeric patterns, and existing keyword regexes.
- Use zone membership as an *additional* signal that refines, never replaces,
  the existing merchant/line-item/amount heuristics.
- Guarantee strictly additive, opt-in-safe behavior: when zones can't be
  reliably detected, every existing heuristic behaves exactly as it does today.
- Stay within this codebase's established "lightweight heuristics over ML"
  precedent (memory/experiments.md's explicit heuristic-over-LLM/ML choice for
  receipt parsing) — no new ML dependency, no new service.
- Keep zone-classification logic in the same layer every other receipt-parsing
  heuristic already lives in: pure, synchronous, unit-testable Dart domain logic.

## Non-Goals

- Not a document-layout ML model (e.g. LayoutLM-style) — rejected; see Tradeoffs.
- Not a rewrite of merchant/line-item/amount extraction — zones are an added
  scoring input, not a replacement for the existing regex cascades.
- Not per-item discount association (linking a "-1.00 DISCOUNT" line to the
  item above it) — a related but distinct problem, explicitly out of scope.
- Not true multi-column layout support (e.g. genuine side-by-side price lists)
  — out of scope for a lightweight heuristic approach; see Edge Cases.
- Not feeding zone labels to the LLM understanding call in v1 — see LLM
  Integration for the sequencing/duplication reasoning behind this.
- Not a fix for e-wallet/bank screenshot parsing — those already bypass the
  entire OCR-heuristic path via the existing `tryParseBankReceipt()` fast path
  in `receipt_parse_pipeline.dart`; layout analysis should not run for them.
- Not a persisted/stored classification — zones are computed in-memory per
  parse, not written to Postgres or Drift (see System Impact).

## Proposed Solution

Two parts:

1. **Server-side geometry extraction** (`services/ocr-api/ocr_api/ocr_engine.py`,
   `_run_tesseract()`): read the per-word `left`/`top`/`width` values
   `pytesseract.image_to_data()` already returns (only `height` is read today)
   and aggregate them per line into a bounding box (min-left, min-top, derived
   max-right/width, existing max-height), expressed as ratios of image
   width/height — the same "ratio relative to this receipt, not absolute
   pixels" convention `height_ratio` already established. Surfaced via an
   extended `OcrLineResult` (`ocr_engine.py`) → `OcrLine` (`models.py`) → the
   client's `lib/domain/models/ocr_line.dart`, mirroring exactly how
   `height_ratio` was threaded through in the 2026-07-08 decision ("Merchant
   candidates ranked by visual prominence").

2. **Client-side zone classification** (new
   `lib/domain/logic/receipt_layout_analyzer.dart`, pure Dart, no network,
   no I/O): walks the (now bbox-carrying) `OcrLine` list and assigns each line
   a zone (header / body / footer / ambiguous) using position/order, height
   ratio, horizontal alignment (left-x clustering for item names, right-x
   clustering for price tokens), and the *same* keyword regexes already
   defined in `merchant_extractor.dart` / `rm_amount_parser.dart` — reused
   directly, not duplicated (`boilerplateHints`, `totalKeywordHints`,
   `discountOrSummaryHints`, the phone/date/address/postcode hints).
   `extractMerchantCandidates`, `extractReceiptLineItems`, and
   `parseRmAmountFromOcr` each gain a new optional `zones` parameter — no-op
   when absent — mirroring the exact pattern `extractMerchantCandidates`'s
   existing `ocrLines` parameter already uses.

## User Experience

Backend/parsing-layer change only — no new UI, no new user-facing state.

- **Golden path**: a receipt whose 4th line is a menu item containing a
  business word ("Kopitiam Fried Rice") — today a real Pass-2 false-positive
  risk in `extractMerchantCandidates` — no longer scores as a merchant
  candidate once it's recognized as inside the body zone rather than the
  header. A bare table-number line that previously risked slipping through
  `extractReceiptLineItems`'s bare-price regex tier as a false item is
  excluded once it's recognized as header/metadata rather than body.
- **No-zones-detected receipt** (very short receipt, heavily garbled OCR, no
  reliable transition found): identical behavior to today — the additive/
  no-op contract by design guarantees zero regression risk here.
- **Already-well-parsed receipt**: no visible change — zone signal only shifts
  scores where there was genuine positional ambiguity to resolve in the first
  place.
- **E-wallet/bank screenshots**: layout analysis never runs — `tryParseBankReceipt()`
  already returns early in `receipt_parse_pipeline.dart` before any heuristic
  extraction (including this new one) is reached.

## System Impact

- **Backend services** (`services/ocr-api` only): `ocr_api/ocr_engine.py`
  (`_run_tesseract()`/`OcrLineResult` gain bbox fields); `ocr_api/models.py`
  (`OcrLine` gains bbox fields, mirroring `height_ratio`'s existing shape).
- **Client application**: `lib/domain/models/ocr_line.dart` (bbox fields, JSON
  round-trip); new `lib/domain/logic/receipt_layout_analyzer.dart`; `merchant_extractor.dart`
  / `receipt_line_item_extractor.dart` / `rm_amount_parser.dart` (each gains an
  optional `zones` parameter); `receipt_parse_pipeline.dart` (threads zones
  through `parseReceiptOcrText`, mirroring how `ocrLines` is already threaded
  into `extractMerchantCandidates` today).
- **Database/storage**: none — zones are a derived, in-memory-only
  classification recomputed on every parse, never persisted to Postgres or
  Drift; no migration.
- **AI/ML pipeline**: none in v1 — explicitly not passed to the LLM
  understanding call (see LLM Integration for why).
- **Infrastructure**: none — no new service, no new dependency.
- **External integrations**: none.

## Technical Design

**Where layout analysis should occur** — split by what each half requires:

- *Raw geometry extraction* is server-only by necessity: pixel-level word
  boxes only exist where Tesseract ran (`ocr_engine.py`). This is a small,
  mechanical extension of an already-computed structure, not a design choice
  with real alternatives.
- *Zone classification* (the actual decision logic) is recommended
  **client-side**, in the Dart domain-logic layer, for the same reason every
  other receipt heuristic already lives there: this codebase has an explicit,
  already-made decision to keep receipt parsing "deterministic, testable,
  offline-capable" (`memory/experiments.md`, heuristic-over-LLM precedent) —
  and it's a pure function over data already in hand, with no reason to round-
  trip it through a server.
- **A real sequencing tension this creates, addressed explicitly**: the LLM
  understanding call (`call_receipt_understanding()`) runs server-side, in
  Python, synchronously inside `POST /ocr`, *before* the client ever receives
  the response. Client-side zone classification necessarily happens *after*
  that call has already completed. This means zone labels cannot reach the LLM
  prompt without either (a) duplicating the (simple, but real) classification
  logic in Python — the same "two ports of one algorithm" risk already
  documented for the Dart/TS geohash encoder in this codebase — or (b) moving
  zone classification server-side entirely, which would contradict the
  domain-logic-lives-in-Dart convention for no compensating benefit. This spec
  recommends neither: see LLM Integration.

**Zone definitions and primary signals**:

- **Header**: the leading run of lines (bounded above by `merchantScanLines`-
  style logic, but made proportional rather than fixed — see Decision Logic)
  containing merchant name, store info, address, contact details. Primary
  signals: early position, large `heightRatio` relative to the receipt's body
  baseline (already computed for the `largeText` merchant pass), horizontally
  centered bbox (store names/logos are often center-aligned, unlike left-
  aligned item rows), and the existing boilerplate/address/phone/date/postcode
  regexes.
- **Body**: the contiguous run of lines matching the shape of an item row —
  primary signal is simply "matches the existing item-line regex cascade in
  `receipt_line_item_extractor.dart`" (quantity/name/price patterns already
  defined there), reinforced by a detected price-column alignment (the right-
  edge x of matched price tokens clustering at a consistent horizontal
  position across candidate body lines).
- **Footer**: the trailing run containing subtotal/tax/service charge/total/
  payment info. Primary signals: trailing position (generalizing the existing
  flat "bottom 20%" heuristic into a real zone boundary), and the existing
  `totalKeywordHints`/`discountOrSummaryHints`/`_extraSummaryLineHints` regexes.
- **Ambiguous**: any line (or, in the worst case, the whole receipt) where
  these signals don't converge on a confident classification — see Decision
  Logic's "handling ambiguous regions."

## Decision Logic

- **Identifying likely header/merchant lines**: a line is header-zone if it's
  within the (proportional) leading window *and* at least one of: matches a
  category-rule keyword, matches a generic business-word hint, has
  `heightRatio` clearing the large-text threshold, or has a horizontally
  centered bbox. A line matching a business-word hint but *outside* the header
  zone (e.g. inside the detected body run) is down-weighted rather than
  treated as a merchant candidate at Pass-2 confidence — directly closing the
  "Kopitiam Fried Rice as menu item" false-positive case from the Problem
  Statement.
- **Identifying likely item/body rows**: a line counts as body only if it
  matches the existing item-regex cascade *and* falls within the detected body
  span *and* isn't independently flagged as header/footer-zone metadata
  (phone/date/postcode/total-keyword) — closing the "bare table-number line"
  gap from the Problem Statement by reusing signals that already exist
  elsewhere in the codebase but weren't shared with the line-item extractor.
- **Identifying likely totals**: within the footer zone, prefer lines matching
  `totalKeywordHints`; among those, prefer ones whose price token's right-edge
  x aligns with the same price column detected in the body zone (a weak but
  free secondary signal — Malaysian receipts don't reliably use a separate
  visual column for totals vs. items, so this never overrides keyword
  evidence, only tiebreaks between otherwise-equal candidates).
- **Handling ambiguous regions**: if no confident body-zone span or footer
  boundary can be detected (no lines match the item-regex cascade at all; no
  total-keyword line found; fewer than a minimum line count to reason about
  structure), the entire classification degrades to "ambiguous" and every
  consuming heuristic behaves exactly as if `zones` were never passed — the
  existing whole-text heuristics are the floor this feature can never regress
  below, by construction, not by exception-handling.
- **Zone boundaries are proportional, not fixed line counts**: the header
  window should scale with receipt length (e.g. bounded by both an absolute
  cap and a fraction of total lines) rather than the current hardcoded
  `merchantScanLines = 15`, and the footer boundary should be derived from the
  detected item-regex-cascade span's end rather than a flat 80%-of-lines cut —
  concrete threshold values are an implementation/tuning detail, not asserted
  as final here.
- **Amount-source semantics unchanged**: zone signal is folded into
  `parseRmAmountFromOcr`'s existing scoring adjustments (alongside the
  existing keyword/position/subtotal-cross-check boosts already in
  `_crossCheckAdjust`) — it does not introduce a new `AmountParseSource` value
  or bypass the existing `itemsMatchTotal`/cross-check machinery. Same
  "additive scoring input, not a new authority" discipline as the OCR-cleanup
  spec's amount-authority constraint.

## LLM Integration

- **Recommendation: do not pass zone labels to the LLM call in v1.** The
  sequencing tension in Technical Design is the reason — zone classification
  is client-side and happens after the server-side LLM call has already run.
  Feeding zones to the LLM would require either duplicating this (simple but
  real) logic in Python, incurring the same two-implementations-to-keep-in-
  sync risk already documented elsewhere in this codebase, or relocating
  classification server-side against its natural home. Neither is justified
  by the benefit at this stage.
- **Does layout reduce LLM token usage?** Honestly, no — not as scoped here.
  Zone tags would be a small *addition* to the prompt (a per-line label), not
  a reduction; a genuine token reduction would require scoping separate LLM
  calls per zone (e.g. only send the body zone for line-item extraction),
  which reintroduces the same multiple-LLM-round-trips cost/latency tradeoff
  the companion OCR-cleanup spec already rejected for the same reasons
  (`LLM_TIMEOUT_SECONDS=25s`, synchronous capture-time critical path). Not
  recommended here either.
- **Does spatial context improve structured extraction?** Plausibly yes, but
  unmeasured — deferred rather than asserted. If a future phase wants this,
  the natural path is to move zone classification server-side (Python) so one
  shared computation feeds both the client heuristics and the LLM prompt,
  avoiding the duplication problem — but that's a bigger, separate decision
  than this spec should make. Recorded as a deferred option, not a plan.
- **Composability note**: the OCR-cleanup spec (this session's companion
  document) already recommends switching the LLM's input from flattened text
  to a per-line(+confidence) array. If zone classification is ever moved
  server-side, that same per-line structure is the natural place to add a zone
  tag — worth remembering as a shared seam between the two specs, not
  something to build now.

## Edge Cases

- **Very small receipts** (a 3-4 line thermal stub — merchant, one item,
  total): header/body/footer zones may collapse to one line each or overlap
  entirely; below a minimum line-count floor, zone detection should not be
  attempted at all — the existing heuristics already handle these receipts
  fine without zones, and forcing a classification onto too little signal
  only risks introducing noise.
- **Long receipts** (supermarket, 30+ items, already capped at
  `maxExtractedLineItems = 30`): the body zone spans many lines; the existing
  cap is unaffected, but the header window's proportionality (Decision Logic)
  matters more here than on a short receipt — a fixed 15-line window is
  already a poor fit for both extremes, which is part of the motivation for
  making it proportional.
- **Restaurant receipts**: often include a bare table/pax number
  (`"Table: 5"`) easily mistaken for an item row by the existing bare-price
  regex tier; the metadata-hint sharing in Decision Logic (reusing
  `merchant_extractor.dart`'s phone/date/postcode patterns inside the
  line-item extractor's zone-aware pass) directly targets this.
- **Supermarket receipts**: dense body zone, per-item discount lines
  interleaved (e.g. an item row followed by a `"-1.00 DISCOUNT"` line) — the
  existing `discountOrSummaryHints` exclusion already drops these wholesale
  from item extraction; zone awareness doesn't associate a discount with its
  preceding item (explicitly out of scope, Non-Goals) and shouldn't be assumed
  to fix this class of noise, only to avoid making it worse.
- **E-wallet screenshots**: already fully bypassed via the existing
  `tryParseBankReceipt()` fast path before any heuristic (including this one)
  runs — layout analysis has nothing to do here and should not attempt to run.
- **Multi-column layouts** (rare, but e.g. a genuine two-column price list):
  out of scope. The underlying OCR line grouping itself (Tesseract's
  `block_num`/`par_num`/`line_num`) already assumes standard single-column
  reading order — solving true multi-column layout would need a real
  document-layout model, which contradicts the lightweight-heuristics
  recommendation this spec makes. Flagged as a known limitation, not solved.
- **Receipts with logos**: a logo is an image, not OCR'd text — it simply
  never appears as a line at all, so the header zone naturally starts at the
  first real text line beneath it. No special handling needed; this edge case
  looks more concerning than it is.
- **Receipts with poor alignment** (crooked photo, imperfect deskew): bbox
  left/top values may be noisy. Mitigated the same way `height_ratio` already
  is — using receipt-relative ratios (fraction of image width/height), not
  absolute pixels — plus the same "ambiguous → fall back to whole-text
  behavior" floor that covers every other low-signal case.
- **Missing totals**: if no footer/total-keyword line is found at all, zone
  detection simply reports no footer — this must never regress
  `parseRmAmountFromOcr`'s existing `AmountParseSource.none`/
  `noAmountPatternFailure` path. Zone detection is read-only signal, never a
  precondition for the existing amount-parsing tiers to run.

## Performance Considerations

- **Server-side cost**: reading `left`/`top`/`width` from a dict
  `pytesseract.image_to_data()` already returns is O(1) extra field access per
  word — no new Tesseract call, no new CPU-heavy operation (unlike, for
  contrast, the illumination-correction spec's large-kernel blur). This is one
  of the cheapest possible additions to the OCR pipeline.
- **Client-side cost**: zone classification is a small number of linear passes
  over a receipt's line list (typically well under `merchantScanLines`/
  `maxExtractedLineItems`-sized, i.e. tens of lines) — the same complexity
  class as the regex cascades that already run per line today. Negligible.
- **Latency**: no new network round trip — the bbox fields ride along in the
  same `/ocr` response payload as `height_ratio` already does, adding a few
  extra floats per line to an already-small JSON body. Zone classification
  itself runs synchronously in the existing client-side parse path, adding no
  measurable wall-clock time.
- **Mobile/server tradeoff**: this is a case where the split recommended in
  Technical Design (geometry server-side where the pixel data lives, decision
  logic client-side where every other receipt heuristic already lives) is
  strictly better than either extreme — no reason to run any ML inference on
  a mobile device for this, and no reason to move the already-fast Dart
  heuristics onto the server, which would require a new round trip and break
  the existing property that heuristic parsing works purely off an already-
  received OCR response.

## Security Considerations

- No new data exposure: zones are computed from data already present in the
  `/ocr` response and never persisted — nothing new crosses a trust boundary.
- Same "additive scoring input, never a new authority" discipline already
  established for amount extraction in Decision Logic — zone signal cannot,
  by construction, introduce a new path by which an incorrect amount or
  merchant reaches a transaction, since it only reweights inputs to scoring
  functions that already exist and are already validated the same way.
- No auth/privacy surface changes — same endpoint, same data, no new consumer.

## Tradeoffs

- **Lightweight heuristics (recommended) vs. an ML document-layout model**: a
  trained layout model (LayoutLM-style) could in principle generalize better
  to unusual layouts, but requires training/fine-tuning data specific to
  Malaysian receipts, a new inference dependency, and packaging/latency cost —
  directly contradicting this codebase's repeated, explicit precedent of
  choosing deterministic heuristics over ML/LLM approaches for receipt parsing
  (`memory/experiments.md`'s heuristic-over-LLM decision) and its general
  "measure the simple thing before adding complexity" culture (CLAHE's
  contrast gate, sharpen's opt-in default). Rejected for this stage; the
  bbox/keyword/height signals already available are enough to meaningfully
  improve on today's line-count-only positional reasoning.
- **Server-side vs. client-side zone classification**: server-side would solve
  the LLM-sequencing tension (LLM Integration) for free, but would move
  decision logic that belongs in this codebase's established domain-logic
  layer onto the server, and would need a second Python implementation to stay
  functionally in sync with the Dart one if both are ever needed — rejected as
  the primary design for the same reasons the merged-vs-separate-call tradeoff
  was resolved in the OCR-cleanup spec (avoid duplicating logic across two
  languages without a forcing requirement).
- **Fixed line-count windows (today) vs. proportional zone boundaries
  (recommended)**: keeping `merchantScanLines = 15` and the flat "bottom 20%"
  cutoff would be a smaller diff, but both are already known-poor fits at the
  extremes (very short or very long receipts) — proportional boundaries are a
  direct, low-risk improvement enabled by having real zone signal to begin
  with.
- **Feeding zone labels to the LLM now vs. deferring**: doing it now would
  require solving the sequencing/duplication problem prematurely, for a
  benefit (does spatial context measurably improve LLM structured extraction?)
  that hasn't been measured yet. Deferred until there's a concrete reason to
  revisit — see LLM Integration.

## Implementation Guidance

**Suggested order of work**:

1. Server: extend `ocr_engine.py`'s `_run_tesseract()`/`OcrLineResult` to
   aggregate per-word `left`/`top`/`width` (already in the pytesseract `data`
   dict) into a per-line bbox, expressed as image-relative ratios — self-
   contained, independently testable, no behavior change to existing fields.
2. Server: thread the new fields through `models.py`'s `OcrLine`.
3. Client: extend `lib/domain/models/ocr_line.dart` to parse/round-trip the
   new bbox fields (mirroring `heightRatio`'s existing shape exactly).
4. Client: build `receipt_layout_analyzer.dart` as a pure function
   (`OcrLine list → per-line zone`) with its own unit tests, independent of
   the three existing extractors — get zone classification correct and
   tested in isolation before wiring it into anything that could regress.
5. Client: add the optional `zones` parameter to `extractMerchantCandidates`,
   `extractReceiptLineItems`, and `parseRmAmountFromOcr`, each following the
   exact no-op-when-absent contract `ocrLines` already establishes in
   `extractMerchantCandidates` — verify via existing tests that omitting the
   parameter is behavior-identical to today.
6. Client: thread `zones` through `receipt_parse_pipeline.dart`'s
   `parseReceiptOcrText`, alongside the existing `ocrLines` threading.
7. Validate via the existing batch tool (`scripts/process_receipts.ps1`) that
   zone-aware scoring measurably improves the two concrete false-positive
   classes named in the Problem Statement, without regressing already-correct
   parses on the same fixture set.

**Files to inspect first**: `services/ocr-api/ocr_api/ocr_engine.py`
(`_run_tesseract`, `OcrLineResult` — confirm pytesseract's `data` dict shape
directly rather than assuming); `ocr_api/models.py` (`OcrLine`);
`lib/domain/models/ocr_line.dart`; `lib/domain/logic/merchant_extractor.dart`
(the regexes to reuse — `boilerplateHints`, phone/date/address/postcode hints,
`_businessWordHints`, the existing `largeText` pass this feature extends);
`lib/domain/logic/receipt_line_item_extractor.dart` (the item-regex cascade
that defines "body-shaped line"); `lib/domain/logic/rm_amount_parser.dart`
(`totalKeywordHints`, `discountOrSummaryHints`, the existing bottom-20%
heuristic this feature generalizes); `lib/features/share/receipt_parse_pipeline.dart`
(the orchestration point where `zones` gets threaded through, same shape as
today's `ocrLines` threading).

**Risks**:

- The single most important discipline to enforce in review: **zones must
  never become a hard filter**. Every consuming function's behavior with
  `zones` omitted (or classified entirely "ambiguous") must be provably
  identical to today's behavior — this is what makes the feature safe to ship
  incrementally. An implementation that accidentally makes zone membership a
  precondition (rather than a scoring nudge) anywhere would reintroduce
  regression risk this design is specifically built to avoid.
- Reusing existing regexes (`boilerplateHints`, `totalKeywordHints`, etc.)
  from `merchant_extractor.dart`/`rm_amount_parser.dart` inside the new
  layout analyzer risks an import-cycle or duplication temptation — these
  should be imported and reused directly (both files already export select
  patterns to each other, e.g. `receipt_line_item_extractor.dart` already
  imports from both), not copy-pasted.
- Confirm pytesseract's actual `image_to_data()` output dict keys (`left`,
  `top`, `width`) against the installed version before implementing — this
  spec assumes the standard pytesseract `Output.DICT` shape but wasn't
  verified against a running instance during this research pass.
- Proportional zone-boundary constants (replacing `merchantScanLines = 15` and
  the flat 80% footer cutoff) need the same "tune against real fixtures via
  `scripts/process_receipts.ps1`" discipline every other tunable constant in
  this codebase already carries — don't ship guessed defaults as final.

## Testing Strategy

- **Region detection accuracy**: a small hand-labeled fixture set (real
  receipt OCR text/lines with each line manually tagged header/body/footer)
  — measure per-line zone-assignment precision/recall for the new analyzer in
  isolation, before it's wired into anything else.
- **Merchant extraction improvement**: reuse the batch-tool-based before/after
  methodology already established for this session's companion specs
  (`scripts/process_receipts.ps1`) — compare `extractMerchantCandidates`'s
  top-candidate accuracy with vs. without the `zones` signal on the same real
  receipt folder, specifically checking the "business word inside an item
  name" false-positive class named in the Problem Statement.
- **Line-item extraction improvement**: same batch tool, comparing
  `extractReceiptLineItems`'s precision (false positives like table numbers
  caught) and recall (real items still extracted) with vs. without zones.
- **Total extraction accuracy**: same, comparing `parseRmAmountFromOcr`'s
  picked amount against ground truth; specifically worth measuring whether
  zone-based footer gating makes some of the existing compensating penalty
  constants (e.g. `_largestItemMimicryPenalty`) less necessary — a concrete,
  falsifiable claim about *why* this should help, not just "should be more
  accurate."
- **Unit tests**, following this codebase's existing one-test-file-per-module
  convention (`test/merchant_extractor_test.dart`,
  `test/receipt_line_item_extractor_test.dart`, `test/rm_amount_parser_test.dart`,
  `test/receipt_parse_pipeline_test.dart` all already exist and should gain
  zone-aware cases; a new `test/receipt_layout_analyzer_test.dart` for the
  classifier itself).
- **Regression guarantee test**: an explicit test asserting that calling each
  of the three existing extractors with `zones` omitted (or all-ambiguous)
  produces byte-identical results to calling them today — the direct,
  automated enforcement of the "never a hard filter" discipline from
  Implementation Guidance.

## Rollout Plan

- Because this feature is additive/no-op-safe by construction (not because of
  an env flag), it doesn't strictly need the kind of opt-in gating the
  OCR-cleanup and illumination-correction specs required (those change an LLM
  prompt/response shape or default image-processing behavior respectively).
  Still recommend one lightweight flag or parameter default for easy disable
  during real-fixture tuning, consistent with this pipeline's general
  preference for a quick kill switch while thresholds are being validated.
- No schema or migration — zones are never persisted.
- Ship server-side bbox extraction and client-side zone classification as
  independent, separately-landable changes (per Implementation Guidance's
  order of work) — the bbox fields are harmless if landed before the
  classifier consumes them (same "optional, ignored if unused" shape
  `height_ratio` already has for any client that doesn't read it).
- Rollback is trivial in either direction: disabling/omitting the `zones`
  parameter reverts every consuming function to today's exact behavior; the
  server-side bbox fields are additive and harmless to leave in place even if
  the client-side feature is rolled back.
