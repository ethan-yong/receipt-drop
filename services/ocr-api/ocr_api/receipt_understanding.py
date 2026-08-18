"""LLM receipt-understanding step: turns raw OCR text into structured
merchant info (corrected name, search queries, address clues, category,
Google Places types, line items, confidences). Called synchronously from
`POST /ocr` (see ocr_api/main.py) so the OCR response is already interpreted by
the time it reaches the client — `enrich-transaction` only calls this
directly (via `POST /understand`) as a fallback for rows that reached it
without a usable precomputed understanding.

Calls an OpenAI-compatible chat endpoint — either the self-hosted
LiteLLM/vLLM gateway (`LLM_PROVIDER=vllm`, the default) or DeepSeek
(`LLM_PROVIDER=deepseek`). Same vars probed by
scripts/inspect_llm_endpoint.py; read from the root .env via
ocr_api/__main__.py's _load_root_dotenv(). Flip `LLM_PROVIDER` to switch.

Field/vocabulary definitions here (VENDOR_CATEGORIES, ALLOWED_PLACE_TYPES,
the system prompt) must stay in sync with
supabase/functions/_shared/receipt_understanding.ts, which still owns
Places-query-building (buildLlmTextQueries/resolveIncludedTypes) and
re-validates whatever this endpoint returns as a second line of defense —
same "two ports of one algorithm" precedent as the Dart/TS geohash encoder
(see memory/dependency_graph.md).

Receipt routing: a keyword classifier (ocr_api/skills/orchestrator.py) picks
the appropriate extraction prompt before each LLM call — no extra round-trip.
Skill prompts live in ocr_api/skills/; restaurant.py is the original prompt
moved verbatim.

OCR cleanup (opt-in via LLM_CLEANUP_ENABLED): the same call additionally asks
for a corrected, line-aligned transcript when per-line OcrLineResult data is
available (POST /ocr only — POST /understand only ever has flattened text
and never requests cleanup). The original OCR text/lines are never replaced;
a per-line edit-distance guard (_apply_cleanup_guard) discards any single
line's "correction" that looks rewritten/hallucinated rather than lightly
fixed, keeping the original for that line. See docs/system/decisions.md.
"""

from __future__ import annotations

import json
import logging
import os

import httpx
from pydantic import BaseModel

from ocr_api.llm_gateway import (
    LlmGatewayError,
    as_positive_float_or_none,
    as_str_or_none,
    call_chat_completion,
    clamp01,
    extract_json_object,
    resolve_llm_config,
)
from ocr_api.ocr_engine import OcrLineResult
from ocr_api.skills import SKILL_PROMPTS, classify_receipt

logger = logging.getLogger("ocr_api.receipt_understanding")

LLM_TIMEOUT_SECONDS = 25.0
MAX_OCR_PROMPT_CHARS = 6_000
# Bumped 700->1200 for the itemized line_items array, then 1200->2200 for the
# OCR-cleanup feature's cleaned_lines array — a full corrected transcript for
# a long receipt (20-30 lines) is a meaningfully larger generation than
# structured fields alone. Re-measure via scripts/process_receipts.ps1
# against real long receipts before trusting this number in production.
LLM_MAX_TOKENS = 2200
MAX_MERCHANT_SEARCH_QUERIES = 3
MAX_LINE_ITEMS = 40

# --- OCR cleanup: opt-in gate + tunable guard thresholds ---------------------
# Read via os.environ.get(...) at call time (not module-import time) so tests
# can monkeypatch.setenv per-test — same convention as PREPROCESS_* flags in
# preprocessing.py.

_DEFAULT_CLEANUP_EDIT_DISTANCE_THRESHOLD = 0.3
_DEFAULT_CLEANUP_MIN_WORDS = 4


def _cleanup_enabled() -> bool:
    return os.environ.get("LLM_CLEANUP_ENABLED", "0") == "1"


def _cleanup_edit_distance_threshold() -> float:
    raw = os.environ.get("LLM_CLEANUP_EDIT_DISTANCE_THRESHOLD", "")
    try:
        return float(raw)
    except ValueError:
        return _DEFAULT_CLEANUP_EDIT_DISTANCE_THRESHOLD


def _cleanup_min_words() -> int:
    raw = os.environ.get("LLM_CLEANUP_MIN_WORDS", "")
    try:
        return int(raw)
    except ValueError:
        return _DEFAULT_CLEANUP_MIN_WORDS


VENDOR_CATEGORIES = {
    "food_and_drink",
    "groceries",
    "transport",
    "travel",
    "shopping",
    "health_beauty",
    "entertainment",
    "services",
    "other",
}

# Places v1 (Table A) types the LLM may return. Mirrors the union of
# DEFAULT_NEARBY_TYPES + VENDOR_CATEGORY_TO_PLACE_TYPES in
# supabase/functions/_shared/receipt_understanding.ts.
ALLOWED_PLACE_TYPES = {
    "restaurant",
    "cafe",
    "bakery",
    "meal_takeaway",
    "meal_delivery",
    "bar",
    "fast_food_restaurant",
    "coffee_shop",
    "food_court",
    "supermarket",
    "grocery_store",
    "convenience_store",
    "market",
    "gas_station",
    "parking",
    "subway_station",
    "train_station",
    "transit_station",
    "taxi_stand",
    "lodging",
    "hotel",
    "airport",
    "travel_agency",
    "clothing_store",
    "shopping_mall",
    "department_store",
    "electronics_store",
    "home_goods_store",
    "hardware_store",
    "shoe_store",
    "book_store",
    "pet_store",
    "sporting_goods_store",
    "jewelry_store",
    "gift_shop",
    "florist",
    "pharmacy",
    "drugstore",
    "hospital",
    "doctor",
    "dental_clinic",
    "beauty_salon",
    "hair_salon",
    "spa",
    "gym",
    "movie_theater",
    "amusement_park",
    "bowling_alley",
    "night_club",
    "tourist_attraction",
    "karaoke",
    "laundry",
    "post_office",
    "bank",
    "atm",
    "car_repair",
    "car_wash",
    "veterinary_care",
    "insurance_agency",
    "ice_cream_shop",
    "dessert_shop",
    "juice_shop",
    "tea_house",
    "steak_house",
    "pizza_restaurant",
    "hamburger_restaurant",
    "seafood_restaurant",
    "vegetarian_restaurant",
    "asian_restaurant",
    "chinese_restaurant",
    "indian_restaurant",
    "indonesian_restaurant",
    "japanese_restaurant",
    "korean_restaurant",
    "thai_restaurant",
    "vietnamese_restaurant",
    "liquor_store",
    "butcher_shop",
    "cell_phone_store",
    "furniture_store",
    "bicycle_store",
    "auto_parts_store",
    "car_dealer",
    "skin_care_clinic",
    "nail_salon",
    "physiotherapist",
    "optician",
    "barber_shop",
}


class ReceiptUnderstandingConfidence(BaseModel):
    merchant: float
    address: float
    category: float
    line_items: float = 0.0


class ReceiptUnderstandingRequest(BaseModel):
    ocr_text: str


class ReceiptLineItemUnderstanding(BaseModel):
    name: str
    price: float | None
    quantity: float | None


class ReceiptLineCorrection(BaseModel):
    """One accepted OCR-cleanup edit — only present for lines the model
    changed *and* the edit-distance guard kept. `line_index` matches the
    position in `ReceiptUnderstandingResponse.cleaned_lines` (and, before
    any prompt-budget truncation, `OcrResponse.lines`)."""

    line_index: int
    original: str
    corrected: str


class ReceiptUnderstandingResponse(BaseModel):
    merchant_name: str | None
    merchant_search_queries: list[str]
    address_text: str | None
    location_clues: list[str]
    vendor_category: str | None
    google_place_types: list[str]
    line_items: list[ReceiptLineItemUnderstanding] = []
    confidence: ReceiptUnderstandingConfidence
    # Skill routing output — stamped by call_receipt_understanding after the
    # LLM call; the LLM itself does not produce this field.
    receipt_type: str | None = None
    # Skill-specific optional fields (payment, grocery, transport skills).
    # All None for restaurant/cafe receipts.
    transaction_date: str | None = None
    amount: float | None = None  # LLM-extracted total (payment/transport)
    payment_method: str | None = None
    transaction_id: str | None = None
    booking_reference: str | None = None
    origin: str | None = None
    destination: str | None = None
    # OCR-cleanup step (opt-in via LLM_CLEANUP_ENABLED) — a corrected,
    # line-aligned transcript, additive alongside (never replacing) the
    # OCR-original text/lines. None when cleanup wasn't attempted (disabled,
    # no per-line data available, too little text, or a rendered prompt too
    # large for the existing budget) or produced nothing the edit-distance
    # guard accepted. `cleaned_lines` is always the same length/order as the
    # OCR lines actually sent to the LLM.
    cleaned_lines: list[str] | None = None
    cleaned_ocr_text: str | None = None
    corrections: list[ReceiptLineCorrection] = []


# Receipt-understanding failures use the same generic gateway-error taxonomy
# every LLM-touching pipeline in this service shares (timeout, non-2xx,
# unparseable content, ...) — see ocr_api/llm_gateway.py. Kept as a
# same-class alias (not a subclass) so every existing `raise
# ReceiptUnderstandingError(...)` / `except ReceiptUnderstandingError` call
# site here and in main.py keeps working unchanged; main.py's
# `@app.exception_handler(ReceiptUnderstandingError)` now also transparently
# covers gateway errors raised by the payment-notification pipeline, since
# both raise the same underlying class.
ReceiptUnderstandingError = LlmGatewayError


def _as_str_list(v: object) -> list[str]:
    if not isinstance(v, list):
        return []
    return [s.strip() for s in v if isinstance(s, str) and s.strip()]


def _as_line_items(v: object) -> list[ReceiptLineItemUnderstanding]:
    """Coerces the LLM's raw `line_items` array, dropping any entry with
    neither a usable name nor a price — same "hint, not authority" stance as
    every other field here."""
    if not isinstance(v, list):
        return []
    items: list[ReceiptLineItemUnderstanding] = []
    for entry in v:
        if not isinstance(entry, dict):
            continue
        name = as_str_or_none(entry.get("name"))
        if name is None:
            continue
        price = as_positive_float_or_none(entry.get("price"))
        quantity = as_positive_float_or_none(entry.get("quantity"))
        items.append(
            ReceiptLineItemUnderstanding(name=name, price=price, quantity=quantity)
        )
        if len(items) >= MAX_LINE_ITEMS:
            break
    return items


# --- OCR cleanup: pure helpers (edit-distance guard, prompt shaping) --------
# Independently unit-testable, following this module's own "hint, not
# authority" discipline and the pure-helper pattern already used elsewhere
# in this pipeline (_calibrate_confidence, _normalize_ocr_amounts in
# ocr_engine.py).


def _levenshtein(a: str, b: str) -> int:
    """Classic O(len(a)*len(b)) edit distance. Receipt lines are short (a
    few dozen chars) so a DP table is plenty fast — no need for a faster
    algorithm or a new dependency."""
    if a == b:
        return 0
    if not a:
        return len(b)
    if not b:
        return len(a)
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, start=1):
        curr = [i] + [0] * len(b)
        for j, cb in enumerate(b, start=1):
            cost = 0 if ca == cb else 1
            curr[j] = min(
                prev[j] + 1,  # deletion
                curr[j - 1] + 1,  # insertion
                prev[j - 1] + cost,  # substitution
            )
        prev = curr
    return prev[-1]


def edit_distance_ratio(original: str, corrected: str) -> float:
    """Bounded 0..1 edit-distance ratio: a legitimate character-confusion
    fix is expected to be low; a rewritten/hallucinated line is expected to
    be high. This is the guard's only signal — deliberately not confidence,
    since a confidently-misread character isn't flagged by Tesseract's own
    confidence either (see docs/system/decisions.md)."""
    longest = max(len(original), len(corrected), 1)
    return _levenshtein(original, corrected) / longest


def _total_word_count(texts: list[str]) -> int:
    return sum(len(t.split()) for t in texts)


def _build_cleanup_line_block(lines: list[OcrLineResult]) -> str:
    """Renders per-line OCR output as the LLM's actual prompt input for
    cleanup, each line numbered and tagged with its own calibrated
    confidence — this structural, one-line-to-one-line format is itself a
    constraint that limits the model's ability to freely restructure or
    invent content, and is a prerequisite for [_apply_cleanup_guard].

    Word-level confidence is inlined only for lines below the enrichment
    threshold (same gate as the client response's selective words list).
    """
    from ocr_api.ocr_engine import word_enrichment_threshold

    threshold = word_enrichment_threshold()
    rendered: list[str] = []
    for i, line in enumerate(lines):
        base = f"[{i}] (confidence {line.confidence:.2f}) {line.text}"
        if line.words and line.confidence < threshold:
            word_tags = " ".join(
                f"{{{w.text}|{w.confidence:.2f}{'|corr' if w.digit_corrected else ''}}}"
                for w in line.words
            )
            base = f"{base}\n  words: {word_tags}"
        rendered.append(base)
    return "\n".join(rendered)


def _build_confidence_tagged_line_block(lines: list[OcrLineResult]) -> str:
    """Same per-line confidence tagging as cleanup, for the main extraction
    prompt when cleanup is off. Separated so the cleanup instruction addendum
    is not required for the tags to be meaningful (see
    [_CONFIDENCE_TAG_INSTRUCTION_ADDENDUM]).
    """
    return _build_cleanup_line_block(lines)


def _select_cleanup_lines(
    lines: list[OcrLineResult] | None,
) -> list[OcrLineResult] | None:
    """Decides whether this request is eligible for LLM cleanup at all.
    Returns None (cleanup not attempted) when: the flag is off; no per-line
    data is available (POST /understand only ever has flattened text); too
    little text exists to safely bound with the edit-distance guard (a
    near-empty input is exactly where hallucination risk is highest); or the
    rendered line block wouldn't fit the existing prompt-char budget (rather
    than truncate mid-transcript and risk a length-mismatched response)."""
    if not lines or not _cleanup_enabled():
        return None
    if _total_word_count([line.text for line in lines]) < _cleanup_min_words():
        return None
    if len(_build_cleanup_line_block(lines)) > MAX_OCR_PROMPT_CHARS:
        return None
    return lines


def _apply_cleanup_guard(
    original_lines: list[str], candidate: object
) -> tuple[list[str] | None, list[ReceiptLineCorrection]]:
    """Defensively coerces the model's claimed `cleaned_lines` against the
    original per-line array, then applies the per-line edit-distance guard —
    a line whose edit-distance ratio exceeds the threshold is discarded
    (original kept) independently of every other line, so one bad line never
    discards an otherwise-good cleanup pass. Any shape mismatch (wrong type,
    wrong length, non-string entries) is treated as "no usable cleanup" for
    the whole line array, not raised — same "hint, not authority" stance as
    every other field in this module."""
    if not isinstance(candidate, list) or len(candidate) != len(original_lines):
        return None, []
    threshold = _cleanup_edit_distance_threshold()
    cleaned: list[str] = []
    corrections: list[ReceiptLineCorrection] = []
    for i, (original, corrected_raw) in enumerate(zip(original_lines, candidate)):
        corrected = corrected_raw.strip() if isinstance(corrected_raw, str) else None
        if not corrected or corrected == original:
            cleaned.append(original)
            continue
        if edit_distance_ratio(original, corrected) > threshold:
            cleaned.append(original)  # looks rewritten, not lightly fixed
            continue
        cleaned.append(corrected)
        corrections.append(
            ReceiptLineCorrection(line_index=i, original=original, corrected=corrected)
        )
    return cleaned, corrections


def _coerce_cleanup_fields(
    candidate: object, cleanup_lines: list[OcrLineResult] | None
) -> tuple[list[str] | None, str | None, list[ReceiptLineCorrection]]:
    """Wraps cleanup post-processing in its own exception boundary: a bug
    here must degrade to "no cleanup fields" rather than propagate, since
    this brand-new code path must never turn an otherwise-successful
    understanding (or /ocr response — see main.py) into a hard failure."""
    if cleanup_lines is None:
        return None, None, []
    try:
        original_texts = [line.text for line in cleanup_lines]
        cleaned, corrections = _apply_cleanup_guard(original_texts, candidate)
        if cleaned is None:
            return None, None, []
        return cleaned, "\n".join(cleaned), corrections
    except Exception:
        logger.exception(
            "OCR-cleanup post-processing raised — discarding cleanup fields "
            "for this response, keeping raw OCR fields intact"
        )
        return None, None, []


# Shared cleanup-instruction addendum, composed onto the routed skill prompt
# at call time (see _skill_prompt_with_cleanup) rather than duplicated into
# each of the skill_prompts files — avoids the copy-paste-drift risk already
# documented for VENDOR_CATEGORIES/ALLOWED_PLACE_TYPES existing in two places
# (docs/system/decisions.md, 2026-07-10 entry).
_CLEANUP_INSTRUCTION_ADDENDUM = (
    "\n\nADDITIONAL TASK — OCR cleanup: the input above is a numbered, "
    "per-line OCR transcript, each line tagged with Tesseract's own "
    'confidence for that line (0-1). Also produce a "cleaned_lines" key '
    "(array of strings, exactly the same length and order as the numbered "
    "input lines — one output string per input line; never merge, split, "
    "reorder, or invent lines). Only fix common, mechanical OCR mistakes: "
    "character confusion (O/0, I/1/l, S/5, B/8, Z/2), broken or merged "
    "words, bad spacing, and an obviously missing symbol (e.g. a missing "
    "decimal point in a price). Leave a line unchanged unless you are "
    "confident of an exact mechanical fix — never rewrite, summarize, "
    "translate, or add words not implied by the original characters. "
    "Receipts may mix English and Malay: correct a word only within its own "
    "language, never into a different-language look-alike word. Prefer "
    "leaving lines above confidence 0.85 unchanged. Copy a line through "
    "unchanged if it is already correct or you are unsure."
)

# Short, cleanup-independent explanation of the confidence-tag format used
# when the main extraction prompt receives tagged lines without requesting
# cleaned_lines. Without this, the LLM may treat "(confidence 0.87)" as
# receipt content rather than metadata.
_CONFIDENCE_TAG_INSTRUCTION_ADDENDUM = (
    "\n\nINPUT FORMAT — The OCR transcript below is numbered per line and "
    "tagged with Tesseract's calibrated confidence for that line (0-1). "
    "Some low-confidence lines also include a compact `words:` annotation "
    "with per-word confidence (and `|corr` when a digit-confusion "
    "correction was applied). Treat the tags as reliability metadata, not "
    "receipt content. Prefer fields read from high-confidence lines when "
    "candidates conflict; do not invent content from low-confidence noise."
)


def _skill_prompt_with_cleanup(base_prompt: str) -> str:
    return base_prompt + _CLEANUP_INSTRUCTION_ADDENDUM


def _skill_prompt_with_confidence_tags(base_prompt: str) -> str:
    return base_prompt + _CONFIDENCE_TAG_INSTRUCTION_ADDENDUM


def parse_receipt_understanding(
    raw: str, *, cleanup_lines: list[OcrLineResult] | None = None
) -> ReceiptUnderstandingResponse | None:
    """Parses + validates a raw LLM completion. Every field is coerced
    defensively (wrong types dropped, confidences clamped, off-vocabulary
    category/place-types discarded, queries capped) — the LLM's output is a
    hint, this function is the authority. Returns None only when there's no
    parseable JSON at all, or nothing actionable survives validation.

    `cleanup_lines`, when passed, is the (possibly prompt-budget-limited)
    per-line array that was actually sent to the LLM for the OCR-cleanup
    task — used to validate/guard the response's `cleaned_lines` key. None
    when cleanup wasn't attempted for this request (see
    [_select_cleanup_lines])."""
    json_text = extract_json_object(raw)
    if json_text is None:
        return None
    try:
        obj = json.loads(json_text)
    except json.JSONDecodeError:
        return None
    if not isinstance(obj, dict):
        return None

    merchant_name = as_str_or_none(obj.get("merchant_name"))

    queries: list[str] = []
    seen: set[str] = set()
    for q in _as_str_list(obj.get("merchant_search_queries")):
        key = q.lower()
        if key in seen:
            continue
        seen.add(key)
        queries.append(q)
        if len(queries) >= MAX_MERCHANT_SEARCH_QUERIES:
            break

    raw_category = as_str_or_none(obj.get("vendor_category"))
    vendor_category = (
        raw_category.lower()
        if raw_category and raw_category.lower() in VENDOR_CATEGORIES
        else None
    )

    place_types: list[str] = []
    seen_types: set[str] = set()
    for t in _as_str_list(obj.get("google_place_types")):
        normalized = t.lower().replace(" ", "_")
        if normalized in ALLOWED_PLACE_TYPES and normalized not in seen_types:
            seen_types.add(normalized)
            place_types.append(normalized)

    confidence_obj = obj.get("confidence")
    confidence_obj = confidence_obj if isinstance(confidence_obj, dict) else {}

    address_text = as_str_or_none(obj.get("address_text"))
    location_clues = _as_str_list(obj.get("location_clues"))
    line_items = _as_line_items(obj.get("line_items"))

    # Skill-specific optional fields — defensive coercion, wrong types → None.
    transaction_date = as_str_or_none(obj.get("transaction_date"))
    amount = as_positive_float_or_none(obj.get("amount"))
    payment_method = as_str_or_none(obj.get("payment_method"))
    transaction_id = as_str_or_none(obj.get("transaction_id"))
    booking_reference = as_str_or_none(obj.get("booking_reference"))
    origin = as_str_or_none(obj.get("origin"))
    destination = as_str_or_none(obj.get("destination"))

    actionable = bool(
        merchant_name
        or queries
        or address_text
        or location_clues
        or line_items
        or amount
        or transaction_id
        or booking_reference
    )
    if not actionable:
        return None

    cleaned_lines, cleaned_ocr_text, corrections = _coerce_cleanup_fields(
        obj.get("cleaned_lines"), cleanup_lines
    )

    return ReceiptUnderstandingResponse(
        merchant_name=merchant_name,
        merchant_search_queries=queries,
        address_text=address_text,
        location_clues=location_clues,
        vendor_category=vendor_category,
        google_place_types=place_types,
        line_items=line_items,
        confidence=ReceiptUnderstandingConfidence(
            merchant=clamp01(confidence_obj.get("merchant")),
            address=clamp01(confidence_obj.get("address")),
            category=clamp01(confidence_obj.get("category")),
            line_items=clamp01(confidence_obj.get("line_items")),
        ),
        transaction_date=transaction_date,
        amount=amount,
        payment_method=payment_method,
        transaction_id=transaction_id,
        booking_reference=booking_reference,
        origin=origin,
        destination=destination,
        cleaned_lines=cleaned_lines,
        cleaned_ocr_text=cleaned_ocr_text,
        corrections=corrections,
    )


def _build_messages(
    ocr_text: str,
    *,
    system_prompt: str,
    cleanup_lines: list[OcrLineResult] | None = None,
    tagged_lines: list[OcrLineResult] | None = None,
) -> list[dict[str, str]]:
    # cleanup_lines has already been budget-checked by _select_cleanup_lines,
    # so it's used verbatim here rather than re-truncated — truncating a
    # numbered per-line block risks a partial last line and a response the
    # guard can't length-match against. tagged_lines (main-prompt confidence
    # tags without cleanup) is likewise pre-checked for budget.
    if cleanup_lines is not None:
        content = _build_cleanup_line_block(cleanup_lines)
    elif tagged_lines is not None:
        content = _build_confidence_tagged_line_block(tagged_lines)
    else:
        content = ocr_text[:MAX_OCR_PROMPT_CHARS]
    return [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": content},
    ]


async def call_receipt_understanding(
    ocr_text: str,
    *,
    http_client: httpx.AsyncClient,
    lines: list[OcrLineResult] | None = None,
) -> ReceiptUnderstandingResponse:
    """Calls the LLM gateway and returns a validated understanding, or raises
    [ReceiptUnderstandingError]. No retry beyond one narrow response_format
    fallback on HTTP 400 — every other failure propagates immediately so the
    caller (enrich-transaction) fails the enrichment rather than falling
    back to weaker heuristics.

    The keyword orchestrator (ocr_api/skills/orchestrator.py) selects the
    appropriate extraction prompt before the LLM call — no extra round-trip.
    The actual HTTP call (config resolution, retry-without-response_format-
    on-400, timeout/non-2xx handling) is shared infrastructure — see
    ocr_api/llm_gateway.py's call_chat_completion — this function only owns
    receipt-specific prompt/message building and response parsing.

    `lines`, when passed (POST /ocr only — POST /understand never has
    per-line data), makes this request additionally eligible for the
    OCR-cleanup task (see [_select_cleanup_lines]); still exactly one LLM
    round trip either way.
    """
    classification = classify_receipt(ocr_text)
    skill_prompt = SKILL_PROMPTS[classification.receipt_type]

    cfg = resolve_llm_config()

    cleanup_lines = _select_cleanup_lines(lines)
    tagged_lines: list[OcrLineResult] | None = None
    if cleanup_lines is not None:
        skill_prompt = _skill_prompt_with_cleanup(skill_prompt)
    elif lines:
        # Main extraction prompt still gets confidence tags when cleanup is
        # off — same rendering, separate instruction explaining the tags.
        candidate = _build_confidence_tagged_line_block(lines)
        if len(candidate) <= MAX_OCR_PROMPT_CHARS:
            tagged_lines = lines
            skill_prompt = _skill_prompt_with_confidence_tags(skill_prompt)
    messages = _build_messages(
        ocr_text,
        system_prompt=skill_prompt,
        cleanup_lines=cleanup_lines,
        tagged_lines=tagged_lines,
    )

    logger.info(
        "calling LLM gateway provider=%s model=%s ocrTextChars=%d",
        cfg.provider,
        cfg.model_name,
        len(ocr_text),
    )
    content = await call_chat_completion(
        messages,
        cfg=cfg,
        http_client=http_client,
        max_tokens=LLM_MAX_TOKENS,
        timeout_seconds=LLM_TIMEOUT_SECONDS,
    )

    understanding = parse_receipt_understanding(content, cleanup_lines=cleanup_lines)
    if understanding is None:
        logger.error(
            "LLM response could not be parsed into a receipt understanding: %r",
            content[:2000],
        )
        raise ReceiptUnderstandingError(
            "llm_unparseable_content",
            "no actionable JSON in LLM response",
            content[:2000],
        )

    # Stamp the classifier result — the LLM prompt does not produce this field.
    understanding.receipt_type = classification.receipt_type

    logger.info(
        "receipt understanding parsed — receiptType=%r, merchant=%r "
        "(confidence=%.2f), category=%r (confidence=%.2f), queries=%d, "
        "placeTypes=%d, lineItems=%d, cleanupCorrections=%d",
        understanding.receipt_type,
        understanding.merchant_name,
        understanding.confidence.merchant,
        understanding.vendor_category,
        understanding.confidence.category,
        len(understanding.merchant_search_queries),
        len(understanding.google_place_types),
        len(understanding.line_items),
        len(understanding.corrections),
    )
    return understanding
