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
"""

from __future__ import annotations

import json
import logging
import os
import re
import time
from dataclasses import dataclass

import httpx
from pydantic import BaseModel

from ocr_api.skills import SKILL_PROMPTS, classify_receipt

logger = logging.getLogger("ocr_api.receipt_understanding")

LLM_TIMEOUT_SECONDS = 25.0
MAX_OCR_PROMPT_CHARS = 6_000
# Bumped from 700 now that a response also carries the itemized line_items
# array — a long mamak/supermarket receipt easily has 20-30 rows.
LLM_MAX_TOKENS = 1200
MAX_MERCHANT_SEARCH_QUERIES = 3
MAX_LINE_ITEMS = 40

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


class ReceiptUnderstandingError(Exception):
    """Raised on any LLM-call failure — timeout, non-2xx, or unparseable
    content. No fallback: callers should surface this as a clear failure,
    not silently degrade to a weaker extraction (see docs/decisions.md)."""

    def __init__(self, code: str, detail: str, raw: str | None = None) -> None:
        super().__init__(detail)
        self.code = code
        self.detail = detail
        self.raw = raw


def _chat_completions_url(base_url: str) -> str:
    base = base_url.rstrip("/")
    api_base = base if base.endswith("/v1") else f"{base}/v1"
    return f"{api_base}/chat/completions"


def _extract_json_object(raw: str) -> str | None:
    """Strips <think>…</think> reasoning blocks and markdown fences, then
    slices from the first "{" to the last "}" — defensive against chatty
    models even with response_format requested."""
    s = re.sub(r"<think>[\s\S]*?</think>", "", raw, flags=re.IGNORECASE)
    fence = re.search(r"```(?:json)?\s*([\s\S]*?)```", s, flags=re.IGNORECASE)
    if fence:
        s = fence.group(1)
    start = s.find("{")
    end = s.rfind("}")
    if start == -1 or end == -1 or end <= start:
        return None
    return s[start : end + 1]


def _clamp01(v: object) -> float:
    try:
        n = float(v)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return 0.0
    if n != n:  # NaN
        return 0.0
    return max(0.0, min(1.0, n))


def _as_str_or_none(v: object) -> str | None:
    if not isinstance(v, str):
        return None
    t = v.strip()
    return t or None


def _as_str_list(v: object) -> list[str]:
    if not isinstance(v, list):
        return []
    return [s.strip() for s in v if isinstance(s, str) and s.strip()]


def _as_positive_float_or_none(v: object) -> float | None:
    if v is None or isinstance(v, bool):
        return None
    try:
        n = float(v)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return None
    if n != n or n < 0:  # NaN or negative
        return None
    return n


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
        name = _as_str_or_none(entry.get("name"))
        if name is None:
            continue
        price = _as_positive_float_or_none(entry.get("price"))
        quantity = _as_positive_float_or_none(entry.get("quantity"))
        items.append(
            ReceiptLineItemUnderstanding(name=name, price=price, quantity=quantity)
        )
        if len(items) >= MAX_LINE_ITEMS:
            break
    return items


def parse_receipt_understanding(raw: str) -> ReceiptUnderstandingResponse | None:
    """Parses + validates a raw LLM completion. Every field is coerced
    defensively (wrong types dropped, confidences clamped, off-vocabulary
    category/place-types discarded, queries capped) — the LLM's output is a
    hint, this function is the authority. Returns None only when there's no
    parseable JSON at all, or nothing actionable survives validation."""
    json_text = _extract_json_object(raw)
    if json_text is None:
        return None
    try:
        obj = json.loads(json_text)
    except json.JSONDecodeError:
        return None
    if not isinstance(obj, dict):
        return None

    merchant_name = _as_str_or_none(obj.get("merchant_name"))

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

    raw_category = _as_str_or_none(obj.get("vendor_category"))
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

    address_text = _as_str_or_none(obj.get("address_text"))
    location_clues = _as_str_list(obj.get("location_clues"))
    line_items = _as_line_items(obj.get("line_items"))

    # Skill-specific optional fields — defensive coercion, wrong types → None.
    transaction_date = _as_str_or_none(obj.get("transaction_date"))
    amount = _as_positive_float_or_none(obj.get("amount"))
    payment_method = _as_str_or_none(obj.get("payment_method"))
    transaction_id = _as_str_or_none(obj.get("transaction_id"))
    booking_reference = _as_str_or_none(obj.get("booking_reference"))
    origin = _as_str_or_none(obj.get("origin"))
    destination = _as_str_or_none(obj.get("destination"))

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

    return ReceiptUnderstandingResponse(
        merchant_name=merchant_name,
        merchant_search_queries=queries,
        address_text=address_text,
        location_clues=location_clues,
        vendor_category=vendor_category,
        google_place_types=place_types,
        line_items=line_items,
        confidence=ReceiptUnderstandingConfidence(
            merchant=_clamp01(confidence_obj.get("merchant")),
            address=_clamp01(confidence_obj.get("address")),
            category=_clamp01(confidence_obj.get("category")),
            line_items=_clamp01(confidence_obj.get("line_items")),
        ),
        transaction_date=transaction_date,
        amount=amount,
        payment_method=payment_method,
        transaction_id=transaction_id,
        booking_reference=booking_reference,
        origin=origin,
        destination=destination,
    )


def _build_messages(ocr_text: str, *, system_prompt: str) -> list[dict[str, str]]:
    truncated = ocr_text[:MAX_OCR_PROMPT_CHARS]
    return [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": truncated},
    ]


# Flip via root `.env` `LLM_PROVIDER=vllm|deepseek`. Keep both provider
# blocks filled in so switching is a one-line change + ocr-api restart.
_DEFAULT_DEEPSEEK_BASE_URL = "https://api.deepseek.com/v1"


@dataclass(frozen=True)
class LlmEndpointConfig:
    provider: str
    base_url: str
    model_name: str
    api_key: str | None
    reasoning_effort: str | None


def resolve_llm_config() -> LlmEndpointConfig:
    """Pick active LLM endpoint from `LLM_PROVIDER` + the matching env block.

    Raises [ReceiptUnderstandingError] with code `server_misconfigured` when
    the active provider's required vars are missing, or the provider name is
    unknown.
    """
    provider = (os.environ.get("LLM_PROVIDER") or "vllm").strip().lower()
    if provider in ("vllm", "litellm", "local"):
        provider = "vllm"
        base_url = os.environ.get("VLLM_BASE_URL", "").strip()
        model_name = os.environ.get("VLLM_MODEL_NAME", "").strip()
        api_key = os.environ.get("VLLM_API_KEY", "").strip() or None
        reasoning_effort = os.environ.get("VLLM_REASONING_EFFORT", "").strip() or None
        missing_hint = "VLLM_BASE_URL/VLLM_MODEL_NAME not set"
    elif provider == "deepseek":
        base_url = (
            os.environ.get("DEEPSEEK_BASE_URL", "").strip()
            or _DEFAULT_DEEPSEEK_BASE_URL
        )
        model_name = os.environ.get("DEEPSEEK_MODEL_NAME", "").strip()
        api_key = os.environ.get("DEEPSEEK_API_KEY", "").strip() or None
        # DeepSeek has no reasoning_effort param (use deepseek-reasoner model
        # instead); ignore VLLM_REASONING_EFFORT so a leftover value doesn't
        # get sent to an API that rejects unknown fields.
        reasoning_effort = None
        missing_hint = "DEEPSEEK_MODEL_NAME not set (and DEEPSEEK_API_KEY recommended)"
    else:
        raise ReceiptUnderstandingError(
            "server_misconfigured",
            f"unknown LLM_PROVIDER={provider!r} (expected vllm or deepseek)",
        )

    if not base_url or not model_name:
        raise ReceiptUnderstandingError(
            "server_misconfigured",
            f"LLM_PROVIDER={provider}: {missing_hint}",
        )

    return LlmEndpointConfig(
        provider=provider,
        base_url=base_url,
        model_name=model_name,
        api_key=api_key,
        reasoning_effort=reasoning_effort,
    )


async def call_receipt_understanding(
    ocr_text: str, *, http_client: httpx.AsyncClient
) -> ReceiptUnderstandingResponse:
    """Calls the LLM gateway and returns a validated understanding, or raises
    [ReceiptUnderstandingError]. No retry beyond one narrow response_format
    fallback on HTTP 400 — every other failure propagates immediately so the
    caller (enrich-transaction) fails the enrichment rather than falling
    back to weaker heuristics.

    The keyword orchestrator (ocr_api/skills/orchestrator.py) selects the
    appropriate extraction prompt before the LLM call — no extra round-trip.
    """
    classification = classify_receipt(ocr_text)
    skill_prompt = SKILL_PROMPTS[classification.receipt_type]

    cfg = resolve_llm_config()

    url = _chat_completions_url(cfg.base_url)
    headers = {"Content-Type": "application/json"}
    if cfg.api_key:
        headers["Authorization"] = f"Bearer {cfg.api_key}"
    messages = _build_messages(ocr_text, system_prompt=skill_prompt)

    def _body(with_response_format: bool) -> dict[str, object]:
        body: dict[str, object] = {
            "model": cfg.model_name,
            "messages": messages,
            "temperature": 0,
            "max_tokens": LLM_MAX_TOKENS,
        }
        if with_response_format:
            body["response_format"] = {"type": "json_object"}
        if cfg.reasoning_effort:
            body["reasoning_effort"] = cfg.reasoning_effort
        return body

    start = time.perf_counter()
    logger.info(
        "calling LLM gateway provider=%s model=%s ocrTextChars=%d",
        cfg.provider,
        cfg.model_name,
        len(ocr_text),
    )
    try:
        resp = await http_client.post(
            url,
            headers=headers,
            json=_body(True),
            timeout=LLM_TIMEOUT_SECONDS,
        )
        if resp.status_code == 400:
            # Some LiteLLM/vLLM backends reject response_format outright —
            # one narrow retry without it.
            resp = await http_client.post(
                url,
                headers=headers,
                json=_body(False),
                timeout=LLM_TIMEOUT_SECONDS,
            )
    except httpx.TimeoutException as exc:
        elapsed = time.perf_counter() - start
        logger.error("LLM gateway timed out after %.2fs", elapsed)
        raise ReceiptUnderstandingError("llm_timeout", str(exc)) from exc
    except httpx.HTTPError as exc:
        elapsed = time.perf_counter() - start
        logger.error("LLM gateway request failed after %.2fs: %s", elapsed, exc)
        raise ReceiptUnderstandingError("llm_fetch_failed", str(exc)) from exc

    elapsed = time.perf_counter() - start

    if resp.status_code != 200:
        body_text = resp.text[:500]
        logger.error(
            "LLM gateway returned HTTP %d after %.2fs: %s",
            resp.status_code,
            elapsed,
            body_text,
        )
        raise ReceiptUnderstandingError(
            f"llm_http_{resp.status_code}", "non-2xx from LLM gateway", body_text
        )

    try:
        payload = resp.json()
        content = payload["choices"][0]["message"]["content"]
        model_used = payload.get("model", cfg.model_name)
    except (ValueError, KeyError, IndexError, TypeError) as exc:
        logger.error("LLM gateway returned an unexpected response shape: %s", exc)
        raise ReceiptUnderstandingError("llm_invalid_response_json", str(exc)) from exc

    understanding = parse_receipt_understanding(content)
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
        "LLM understanding ok in %.2fs (model=%s) — receiptType=%r, "
        "merchant=%r (confidence=%.2f), category=%r (confidence=%.2f), "
        "queries=%d, placeTypes=%d, lineItems=%d",
        elapsed,
        model_used,
        understanding.receipt_type,
        understanding.merchant_name,
        understanding.confidence.merchant,
        understanding.vendor_category,
        understanding.confidence.category,
        len(understanding.merchant_search_queries),
        len(understanding.google_place_types),
        len(understanding.line_items),
    )
    return understanding
