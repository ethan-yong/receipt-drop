# Feature: LLM-Based OCR Cleanup & Correction Stage

## Overview

A cleanup step that corrects common, mechanical Tesseract OCR mistakes — character
confusion (O/0, I/1/l, S/5, B/8, Z/2), broken words, bad spacing, missing symbols,
misread totals — while always preserving the original OCR output alongside the
corrected version. Rather than adding a new LLM call, this extends the pipeline's
existing single synchronous LLM step (`call_receipt_understanding()` in
`services/ocr-api/ocr_api/receipt_understanding.py`, called from `POST /ocr` in
`ocr_api/main.py`) with new response fields, keeping the pipeline at one LLM round
trip per receipt.

## Problem Statement

The pipeline has exactly one existing mitigation for OCR character confusion
today: `_normalize_ocr_amounts()` in `ocr_engine.py`, a narrow regex that fixes
Z/z/O/l/I-style digit confusion but *only* inside text matching `RM<amount>` —
it does nothing for broken/misspaced words, missing symbols, or character
confusion anywhere else on the receipt (merchant names, item names). The existing
LLM understanding step does implicitly "correct" a few fields as a byproduct of
extraction (`merchant_name`, `line_items`, skill-specific `amount`), but produces
no corrected full-text transcript — nothing in the pipeline today improves the
raw OCR text/lines themselves, which matters because the client's heuristic Dart
extractors (`receipt_line_item_extractor.dart`, `rm_amount_parser.dart`,
`category_matcher_bundled.dart`) parse that raw text directly and run regardless
of whether the LLM call succeeds (2026-07-10 decision: "heuristic extraction
always still runs first ... its subtotal feeds the amount-parsing cross-check").
A receipt with `"T0TAL RM5O.OO"` or `"RESTORAN AME"` (real, documented OCR
failure modes elsewhere in this repo's decisions log) degrades both the LLM's own
extraction and that heuristic cross-check, with nothing today addressing the
underlying garbled text both paths consume.

## Goals

- Correct common, mechanical OCR errors (character confusion, broken words,
  spacing, missing symbols, misread totals) while preserving receipt meaning.
- Always preserve the original OCR output — corrected text is additive, never a
  replacement, and traceable back to what OCR actually produced.
- Constrain corrections to low-risk, bounded edits; avoid hallucinating content
  not present in the original scan.
- Reuse the existing single synchronous LLM call rather than adding a second
  LLM round trip, following this codebase's established "merge synchronous
  steps" precedent (2026-07-10 decision).
- Improve input quality for *two* existing consumers that both read raw OCR
  text/lines today: the LLM's own structured extraction, and the client's
  heuristic Dart parser/cross-check.

## Non-Goals

- Not a rewrite of `call_receipt_understanding()`, the skill-routing system, or
  Places-matching logic — those stay as-is.
- Not a second, independent LLM call or service — explicitly rejected as the
  primary design (see Tradeoffs).
- Not a replacement for `_normalize_ocr_amounts()` — that narrow, zero-latency
  regex fix for digit confusion inside `RM` amounts stays as a fast first pass;
  this feature is a broader complement, not a replacement.
- Not a redesign of client trust in `understanding` (2026-07-10 decision) —
  cleaned text is additive to that trust model.
- Not full cross-language translation — receipts may mix English/Malay
  (`TESSERACT_LANG=eng+msa` is already a deliberate config choice); corrections
  must stay within the original token's language, not translate it.
- Not an image-level fix — this operates purely on already-extracted OCR text,
  downstream of Tesseract and any preprocessing-stage work (e.g. the
  illumination-correction spec drafted alongside this one).
- Not a new authoritative source for financial amounts — `transactions.amount_myr`
  continues to be derived exclusively through the existing heuristic-parser/
  structured-field/cross-check pipeline; this feature never introduces a second
  path by which a dollar figure reaches that column (see Decision Logic, Security
  Considerations — this is the single most important non-goal here).

## Proposed Solution

Extend `ReceiptUnderstandingResponse` (and the LLM call that produces it) with a
cleaned, line-aligned OCR transcript and a compact per-line correction record,
instead of adding a second "cleanup" LLM call before understanding. The five
existing skill system prompts (`ocr_api/skills/{restaurant,cafe,grocery,payment,
transport}.py` — confirmed via `ocr_api/skills/orchestrator.py`'s `SKILL_PROMPTS`)
gain a shared cleanup-instruction block (one shared string composed into each,
not five independently maintained copies). The prompt's input changes from a
flattened `ocr_text` string to the already-available per-line array (currently
discarded down to `OcrLine{text, height_ratio}` before reaching the LLM), plus a
new per-line confidence figure aggregated from the per-word Tesseract confidences
`_run_tesseract()` already computes in `ocr_engine.py` but currently discards
after computing the overall mean. Confidence lets the prompt instruct the model
to leave high-confidence lines untouched and concentrate correction effort on
low-confidence ones — directly serving "avoid changing what shouldn't be changed."

A cheap, non-LLM guard runs after the response is parsed, before anything is
persisted or returned: for every line the model claims to have corrected, compute
a bounded edit-distance ratio between original and corrected text. A ratio beyond
a tunable threshold (a legitimate character-confusion fix should be low-distance;
a rewritten/hallucinated line should be high-distance) causes that specific
line's correction to be discarded and the original kept — per line, not
all-or-nothing for the whole receipt.

## User Experience

Backend-only change — no new UI, no new user-facing state, same shape as the
illumination-correction feature.

- **Golden path**: a receipt with `"RESTORAN AME"` / `"T0TAL RM5O.00"`-style
  noise gets a corrected transcript back in the same `/ocr` response used today.
  Both the LLM's structured fields and the client's heuristic extractor (now fed
  the cleaned text alongside the original) have a better shot at a correct
  merchant/amount — fewer receipts should need the `needs_review` queue.
- **Already-clean OCR**: cleaned lines return identical or near-identical to
  originals; the edit-distance guard shows near-zero deltas; behavior is
  unchanged from today.
- **Guard-rejected correction**: a specific line's correction is silently
  discarded and the original kept for that line — invisible to the user, logged
  for tuning, the same invisible-fallback shape used by the illumination-
  correction spec's own quality guards and by `shadow_binarize()`'s existing
  degenerate-output fallback.
- **LLM failure**: identical to today — `/ocr` still succeeds with raw OCR
  fields only, `understanding_error` set, cleaned fields simply absent. Every
  downstream consumer already handles `understanding: null` correctly.
- **Traceability**: `raw_ocr_text` (already always persisted per the 2026-07-09
  decision) remains untouched ground truth. A new, clearly-separate
  `cleaned_ocr_text` field lets anyone debugging a bad extraction see both what
  OCR actually saw and what cleanup changed — extending the existing debugging
  workflow already documented in `main.py` ("so a bad LLM extraction ... can be
  traced back to what OCR actually saw").

## System Impact

- **Backend services** (`services/ocr-api` only):
  - `ocr_api/receipt_understanding.py` — `ReceiptUnderstandingResponse` gains
    optional cleanup fields; `_build_messages()`/`_body()` input changes from
    flattened text to per-line(+confidence) structure; `parse_receipt_understanding()`
    gains defensive parsing plus the edit-distance guard for the new fields;
    skill prompts gain the shared cleanup-instruction addendum.
  - `ocr_api/ocr_engine.py` — `_run_tesseract()`/`OcrLineResult` need to surface
    per-line aggregated confidence (the per-word `conf` values are already
    computed, currently discarded after the mean).
  - `ocr_api/models.py` — `OcrLine` gains a confidence figure so it can flow
    through to `receipt_understanding.py` (whether it's also exposed in the
    client-facing response is an implementation choice, not required for this
    feature's core value).
  - `ocr_api/main.py` — no route-shape change, same call sequence.
- **Client application**: `lib/features/share/receipt_parse_pipeline.dart` and
  the heuristic extractors gain a new optional input (cleaned text/lines) to
  prefer over raw OCR text when present, without changing the existing
  heuristic-vs-LLM-structured-field precedence order (2026-07-10 decision).
  Drift needs a new local column mirroring `llmUnderstandingJson`'s v6→v7
  addition from that same decision.
- **Database/storage**: new Postgres column(s) on `transactions` —
  `cleaned_ocr_text` (text) plus a compact corrections record (either its own
  jsonb column or folded into the existing `llm_understanding` jsonb blob) — new
  migration following the pattern of `20260709000000_llm_understanding.sql`.
- **AI/ML pipeline**: the one existing LLM call's prompt and response schema
  grow. `LLM_MAX_TOKENS` (1200 today, already bumped once for `line_items`)
  will very likely need another bump to fit a full cleaned transcript.
- **Infrastructure**: none — no new service, no new dependency, same LLM
  gateway (`VLLM_*`/DeepSeek) already in use.
- **External integrations**: none.

## Technical Design

**Processing placement** — the user's four options, evaluated directly:

- *Inside receipt understanding* (recommended): extend the existing single
  call's response schema, as described above. One LLM round trip, reuses
  already-paid-for latency/cost budget.
- *Before receipt understanding, as a separate call*: cleaner separation of
  concerns, independently testable/versionable — but doubles LLM round trips on
  the heaviest latency contributor in the pipeline (`LLM_TIMEOUT_SECONDS=25s`,
  synchronous, capture-time), and duplicates correction work the existing call
  already partially does. Rejected as primary design; see Tradeoffs for the full
  comparison.
- *After receipt parsing*: rejected outright — cleanup's value is specifically
  as an input to extraction/parsing; correcting after parsing has already
  guessed is too late to help.
- *Fallback only* (cleanup runs only on low-confidence receipts): would save
  cost under a separate-call design, but is moot once merged — the call already
  runs on every receipt with any text, so gating cleanup specifically adds
  branching complexity for no savings. Also misses medium-confidence receipts
  (e.g. 0.6 mean confidence) that can still have a garbled total or merchant
  name buried among otherwise-fine text.

**Input shape**: the per-line array (`list[OcrLineResult]` in `ocr_engine.py`,
already produced, currently flattened to a single string before reaching the
LLM) becomes the prompt's actual input, each line annotated with its aggregated
confidence. This keeps the model's corrected output structurally aligned
one-line-to-one-line with the original — a structural constraint that itself
limits the model's ability to freely restructure or invent content, and is a
prerequisite for the per-line edit-distance guard described below.

**Output shape**: a cleaned line array (same line count/order as input) plus a
compact per-line correction record for lines that changed (original text,
corrected text — no separate free-form "explanation" field, since that widens
the hallucination surface for no functional benefit). This sits alongside, not
instead of, the existing structured fields (`merchant_name`, `line_items`, etc.)
in the same response object.

**Guard placement**: the bounded per-line edit-distance check runs entirely
inside `parse_receipt_understanding()` (or a helper it calls), after JSON
parsing and before the response object is returned to `main.py` — consistent
with that function's existing role as "the LLM's output is a hint, this function
is the authority" for every other field.

## Decision Logic

- **When cleanup is attempted**: exactly when the existing structured-
  understanding call already runs — whenever OCR produced non-empty text
  (`text.strip()` in `main.py`). No new gate; inherited for free from the merge.
- **Per-line correction guidance**: the prompt instructs the model to leave
  lines above a confidence threshold unchanged and to prefer minimal, targeted
  edits on any line, high- or low-confidence.
- **Per-line accept/reject**: after parsing, for every line where corrected ≠
  original, compute an edit-distance ratio (edits ÷ max(len(original),
  len(corrected))). Above a tunable threshold, discard that line's correction
  and keep the original — a legitimate few-character-confusion fix is expected
  to be low-distance; a rewritten or invented line is expected to be
  high-distance. This runs per line, so one bad line doesn't discard an
  otherwise-good cleanup pass.
- **Low-text floor**: when recognized word/line count falls below a small
  threshold, skip cleanup entirely (cleaned fields stay null) rather than let
  the model "fill in" a plausible-sounding receipt from a fragment — the
  edit-distance guard can't meaningfully bound a near-empty input.
- **Missing cleanup fields in an otherwise-valid response**: treated exactly
  like a missing/failed understanding today — `cleaned_lines`/`cleaned_ocr_text`
  stay null, no error raised. Cleanup and structured extraction are validated
  and consumed independently within the same response, not all-or-nothing.
- **LLM call failure**: unchanged from today's `ReceiptUnderstandingError` path
  — `understanding=null`, `understanding_error` set, no cleaned text either. A
  pure superset of existing failure handling; nothing new to build here.
- **Client trust**: cleaned text is a "hint, not authority," identical to every
  other LLM-derived field in this codebase. The heuristic Dart parser's
  existing cross-checks (subtotal-vs-total, amount plausibility) apply
  identically whether they ran against raw or cleaned text — cleaned text is a
  better *input* to existing validation, never a bypass of it.
- **Amount authority (hard constraint)**: `cleaned_ocr_text` is never itself
  parsed for amounts by any new code path. `transactions.amount_myr` continues
  to be derived exclusively via the existing heuristic-parser/structured-field/
  cross-check pipeline (`line_items`, skill `amount`, and the existing
  heuristic subtotal cross-check) — this feature adds no new route to that
  column. When a corrected total disagrees materially with the heuristic
  line-item sum, today's existing "prefer heuristic, flag for review" behavior
  is unchanged.
- **`raw_ocr_text` immutability**: never overwritten under any circumstance —
  written once at ingest (2026-07-09 decision); this feature only ever adds a
  parallel `cleaned_ocr_text`.

## Edge Cases

- **Low-confidence OCR with very little text** (2-3 recognized words): high
  hallucination risk if the model "fills in" a plausible receipt from a
  fragment. Mitigated by the explicit low-text floor (Decision Logic) — cleanup
  is skipped entirely rather than guarded after the fact, since the
  edit-distance guard can't meaningfully bound a near-empty input.
- **Unusual merchant formats** (hand-stamped receipt books, invoice-style
  bills): the keyword skill classifier (`classify_receipt`) may misclassify.
  Cleanup instructions must be skill-agnostic/generic rather than tuned per
  skill, since correct cleanup matters more broadly than getting skill-specific
  structured fields right, and shouldn't depend on correct classification the
  way those fields do.
- **Handwritten receipts**: Tesseract (trained for printed text) produces
  especially high-entropy output on handwriting; the LLM may either safely
  produce near-empty corrections or dangerously hallucinate plausible printed
  text from illegible fragments. No handwriting-specific detection exists in
  this pipeline today — the low-confidence/low-text floor is the only (imperfect)
  mitigation, since Tesseract's own confidence on handwriting is typically
  already very low in practice. Document as a known limitation, not a solved case.
- **Multiple languages** (English/Malay mixed — `TESSERACT_LANG=eng+msa` is
  already a deliberate, documented config choice): the shared cleanup prompt
  must explicitly instruct the model that receipts may mix languages and that
  corrections must stay within the original token's language — never
  "correcting" a Malay word into a similar-looking English one or vice versa.
- **Incorrect OCR that looks plausible** (e.g. Tesseract confidently misreads
  `"RM15.00"` as `"RM75.00"` — a real digit swap producing another entirely
  valid-looking amount): the hardest case. The edit-distance guard does *not*
  help here — a single-digit price swap has the same low edit distance as a
  legitimate fix, and no purely textual guard can distinguish a correct
  single-character fix from an incorrect one. Mitigated structurally, not
  textually: amount authority stays with the existing heuristic cross-check
  machinery (see Decision Logic's hard constraint), so an LLM digit-swap
  mistake in `cleaned_ocr_text` cannot, by construction, become the transaction's
  recorded amount.
- **Amount correction mistakes**: same mitigation as above — no new
  amount-of-record is introduced by this feature; blast radius is capped by
  existing unchanged cross-check machinery.
- **Merchant name over-correction** (the model "fixes" a real, unusually-spelled
  business name into a more common but wrong one): `merchant_name` is already
  an existing LLM-derived field with this pre-existing risk, not newly
  introduced by this feature. What *is* new: the cleaned transcript's merchant
  line could independently diverge from the same response's structured
  `merchant_name` field if the two aren't generated consistently — an
  internal-consistency risk worth testing for (see Testing Strategy), not one
  this design claims to solve architecturally.

## Performance Considerations

- **Latency**: folded into the existing, already-paid-for LLM call
  (`LLM_TIMEOUT_SECONDS=25s`, already on the synchronous `/ocr` critical path
  per the 2026-07-10 decision) — the *additional* cost is a longer prompt
  (per-line + confidence structure instead of flattened text) and a longer
  generated response, not a whole new network round trip. This is the central
  performance argument for the merged design over a separate call, which would
  add a second full LLM round trip on the pipeline's heaviest-latency step.
- **Cost**: token cost per request increases (longer input + output) but stays
  at one LLM call per receipt rather than two — a separate-call design would
  roughly double per-receipt LLM cost, independent of the latency argument.
- **`LLM_MAX_TOKENS` re-tuning**: 1200 today (already bumped once for
  `line_items`); a full cleaned transcript for a long receipt (20-30 lines, per
  the existing in-code comment about mamak/supermarket receipts) adds
  meaningfully to output size — a concrete implementation task, not a footnote.
- **`MAX_OCR_PROMPT_CHARS`** (6000 today) stays unchanged — cleanup, like
  structured extraction today, only ever sees the same truncated input window;
  a receipt long enough to be truncated already loses structured-extraction
  accuracy on its tail today, so this isn't a new limitation.
- **Caching**: not applicable. Unlike the merchant-alias cache (keyed on
  merchant+geohash, reused across repeat visits to the same place), each
  receipt image is unique — there's no natural repeat key for OCR text/cleanup
  to hit against, so no caching layer is proposed.
- **Sync vs. async**: stays synchronous, inside the same `/ocr` request — the
  explicit point of the 2026-07-10 merge decision was that "the app has an
  already-cleaned receipt ... the moment OCR returns," not after a later
  background round trip. Deferring cleanup to an async step (e.g. alongside
  Places matching in `enrich-transaction`) would reintroduce exactly the
  "raw-OCR-first, corrected-later" experience that decision moved away from.

## Security Considerations

- **Preventing hallucinated values**: primary mitigation is the per-line
  bounded edit-distance guard plus the low-text floor. Explicitly acknowledged
  residual risk: a plausible-looking wrong digit substitution (Edge Cases) is
  not caught by any textual guard — this is precisely why amount authority is
  kept with the existing heuristic cross-check machinery rather than ever
  routed through cleaned text (see Decision Logic's hard constraint).
- **Auditability**: `cleaned_ocr_text` stored alongside — never replacing —
  `raw_ocr_text`, plus a compact per-line corrections record, gives a human
  reviewer (or a future automated eval) a clear diff to inspect.
- **Avoiding incorrect financial data extraction**: this feature introduces no
  new path by which a dollar amount reaches `transactions.amount_myr` — that
  value remains derived exclusively through the existing heuristic-parser/
  structured-field/cross-check pipeline, unchanged. This is the single most
  important reliability property of this design and is stated as a hard
  constraint (Decision Logic), not an implication.
- **Auth/data privacy**: no new surface — same `X-OCR-Secret`-gated `/ocr`
  endpoint, same LLM gateway already trusted with full OCR text today.

## Tradeoffs

- **Merged single call (recommended) vs. separate cleanup call before
  understanding**: a separate call gives cleanup a genuinely cleaner single
  responsibility and independent testability/versioning. Rejected as the
  primary design because it roughly doubles LLM round trips (and cost) on the
  pipeline's heaviest latency contributor, and because the existing structured-
  extraction call already implicitly performs overlapping correction work
  (merchant name, amounts, line items) — a separate pass first would pay for
  that correction twice, in different forms.
- **Full cleaned-transcript output vs. structured-field-only corrections**: a
  structured-field-only approach (extend only `merchant_name`/`line_items`/
  amount, no free-form cleaned lines) would be lower-risk — smaller output
  surface, easier to validate field-by-field. Rejected because it wouldn't help
  the client's existing heuristic Dart extractor, which parses raw OCR
  text/lines directly and runs regardless of LLM success as a cross-check
  (2026-07-10 decision). A full cleaned transcript benefits that path too; the
  larger validation surface this requires is mitigated via the per-line
  edit-distance guard.
- **Per-line edit-distance guard vs. a confidence-threshold-only guard**: a
  purely confidence-based guard (trust corrections only on already-low-
  confidence lines) is backwards for the "plausible wrong digit swap" case — a
  confidently-misread character is, by definition, not flagged by Tesseract's
  own confidence, so a confidence-only guard would let through exactly the
  hardest, most dangerous corrections while blocking easy, safe ones.
  Edit-distance is a different, complementary axis (how much text changed, not
  how confident OCR was); confidence is used only to guide the model's
  attention in the prompt, not as the safety guard itself.
- **Skill-agnostic shared cleanup instruction vs. per-skill-tuned cleanup
  prompts**: per-skill tuning could theoretically improve precision for each
  receipt type, but risks copy-paste drift across five independently-maintained
  prompt files (`ocr_api/skills/*.py`, confirmed to be independent prose today,
  not templated) and depends on the keyword classifier having gotten
  classification right in the first place — a dependency structured-field
  extraction already accepts but cleanup shouldn't need to. A single shared
  instruction block composed into all five prompts is simpler and doesn't
  inherit that dependency.

## Implementation Guidance

**Suggested order of work**:

1. Extend `ocr_engine.py`'s `_run_tesseract()`/`OcrLineResult` to surface
   per-line aggregated confidence (the per-word `conf` values are already
   computed and currently discarded after the mean) — self-contained,
   independently testable.
2. Extend `models.py`'s `OcrLine` (or an internal-only structure) to carry that
   confidence through to `receipt_understanding.py`.
3. Add the shared cleanup-instruction prompt addendum, composed into all five
   skill prompts (`ocr_api/skills/*.py`) rather than duplicated per file.
4. Extend `ReceiptUnderstandingResponse`/`parse_receipt_understanding()` with
   the new optional cleanup fields and their defensive coercion, following the
   exact "hint, not authority" validation style already used for every other
   field in that function.
5. Implement the per-line edit-distance guard and the low-word-count skip
   floor as pure, independently unit-testable functions — following this
   file's existing pattern for pure helpers (`_calibrate_confidence` in
   `ocr_engine.py`, `_normalize_ocr_amounts`).
6. Bump `LLM_MAX_TOKENS` and re-measure actual response sizes against real long
   receipts via `scripts/process_receipts.ps1`.
7. Wire client-side consumption: new Drift column mirroring the
   `llmUnderstandingJson` v6→v7 pattern, new Postgres migration mirroring
   `20260709000000_llm_understanding.sql`, and thread cleaned text into
   `receipt_parse_pipeline.dart`'s heuristic extractors as a preferred
   alternative input to raw OCR text/lines — without changing the existing
   heuristic-vs-LLM-structured-field precedence order.

**Files to inspect first**: `services/ocr-api/ocr_api/receipt_understanding.py`
(the call/schema/parsing to extend); `ocr_api/ocr_engine.py` (`_run_tesseract`,
`OcrLineResult`, and `_normalize_ocr_amounts` — understand the existing narrow
fix this complements, don't duplicate it); `ocr_api/skills/orchestrator.py` and
one skill file (e.g. `ocr_api/skills/restaurant.py`) to see exactly how a shared
cleanup addendum threads in without duplicating text across five files;
`ocr_api/models.py`; `ocr_api/main.py` (route shape, unchanged);
`supabase/migrations/20260709000000_llm_understanding.sql` (migration pattern to
follow). `lib/features/share/receipt_parse_pipeline.dart` was **not** read during
this spec's research — the implementing agent should read it directly before
wiring client-side consumption, since this document's grounding stops at the
server boundary.

**Risks**:

- The "hint, not authority" discipline must extend cleanly to the new fields —
  under time pressure it would be tempting to let a "corrected amount" flow
  directly into `transactions.amount_myr` since it's sitting right in the same
  response object. The hard constraint in Decision Logic exists specifically to
  head this off and should be treated as non-negotiable, not a suggestion.
- `LLM_TIMEOUT_SECONDS` (25s) and the synchronous-capture-critical-path design
  are already tight; a longer prompt/response eats into that budget. Measure
  actual added latency via the batch tool before considering this shippable —
  don't assume it's negligible just because it avoids a second round trip.
- The five skill prompt files are independent prose today (confirmed by
  inspection, not templated) — a naive implementation risks copy-paste drift
  across them if the cleanup addendum isn't centralized as a single shared
  string composed into each.
- `docs/system/decisions.md` has no entry documenting the skill-orchestrator
  system (`ocr_api/skills/`) despite it being real, shipped, load-bearing code
  discovered during this research — a pre-existing documentation gap; don't
  assume it's speculative/unused because it's undocumented in the decisions log.

## Testing Strategy

- **OCR correction accuracy evaluation**: extend the existing batch tool
  (`scripts/process_receipts.ps1` / `bin/process_receipts.dart`) run against a
  folder of real receipts with manually-verified correct amounts/merchant
  names; compare structured-field accuracy and, new for this feature, line-level
  correction precision/recall against a small hand-labeled sample.
- **False-correction detection**: a dedicated test category, separate from
  "does it fix real errors" — feed already-correct, high-confidence fixtures
  through the cleanup path and assert zero/near-zero line changes. This is the
  direct test of "avoid changing what shouldn't be changed."
- **Unit tests** (`services/ocr-api/tests/test_receipt_understanding.py`,
  existing file, uses `httpx.MockTransport` — no real network/gateway): mock LLM
  responses containing both legitimate low-edit-distance corrections and
  deliberately-pathological high-edit-distance ones, asserting the guard keeps
  the former and reverts the latter; mock a response and assert the request
  payload the mock receives actually includes per-line confidence (verifying
  the "leave confident lines alone" instruction has real data behind it, not
  just prompt text).
- **Receipt extraction improvement measurement**: same batch-tool before/after
  comparison used for the illumination-correction feature — run the existing
  fixture/receipt folder with the feature off vs. on, diff calibrated
  confidence, word/line counts, and (via `-E2e`) downstream parse success.
- **Human review criteria**: for any correction the automated guards accept, a
  manual spot-check should ask (a) did this correction preserve the receipt's
  actual meaning, not just look plausible; (b) would a native reader of the
  receipt's language(s) agree with the correction; (c) does the cleaned
  transcript's merchant line agree with the same response's structured
  `merchant_name` field (the internal-consistency risk flagged in Edge Cases).
  These three questions form the explicit audit rubric, not "does this look
  better."

## Rollout Plan

- Ships env-gated, following this pipeline's existing opt-in-stage convention
  (`PREPROCESS_CLAHE`, `PREPROCESS_SHARPEN`, etc. in `preprocessing.py` — same
  repo-wide pattern, applied here to whether cleanup fields are requested from
  the LLM at all). Recommend defaulting off until real-fixture-validated via the
  batch tool, then flipping on — mirroring the illumination-correction spec's
  staged-rollout recommendation.
- Because this changes the LLM call's prompt/response shape (not just a
  downstream postprocessing step), verify the existing `response_format`/HTTP-400
  retry-without-response_format fallback in `call_receipt_understanding()` still
  behaves correctly against the larger schema before flipping the flag on for
  real traffic.
- No schema-breaking risk to existing consumers: new fields are additive/optional
  on `ReceiptUnderstandingResponse`, matching this codebase's own stated
  backward-compatibility discipline (`OcrLine`'s doc comment: "optional so an
  older client reading just text/confidence is unaffected" — same shape reused
  here).
- Rollback is disabling the flag and redeploying `services/ocr-api` — stateless,
  no migration to reverse server-side. New Postgres columns/Drift column can
  stay in place unused if rolled back (additive, non-breaking to leave dormant).
