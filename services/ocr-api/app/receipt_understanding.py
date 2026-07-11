"""LLM receipt-understanding step: turns raw OCR text into structured
merchant info (corrected name, search queries, address clues, category,
Google Places types, line items, confidences). Called synchronously from
`POST /ocr` (see app/main.py) so the OCR response is already interpreted by
the time it reaches the client — `enrich-transaction` only calls this
directly (via `POST /understand`) as a fallback for rows that reached it
without a usable precomputed understanding.

Calls an OpenAI-compatible chat endpoint — either the self-hosted
LiteLLM/vLLM gateway (`LLM_PROVIDER=vllm`, the default) or DeepSeek
(`LLM_PROVIDER=deepseek`). Same vars probed by
scripts/inspect_llm_endpoint.py; read from the root .env via
app/__main__.py's _load_root_dotenv(). Flip `LLM_PROVIDER` to switch.

Field/vocabulary definitions here (VENDOR_CATEGORIES, ALLOWED_PLACE_TYPES,
the system prompt) must stay in sync with
supabase/functions/_shared/receipt_understanding.ts, which still owns
Places-query-building (buildLlmTextQueries/resolveIncludedTypes) and
re-validates whatever this endpoint returns as a second line of defense —
same "two ports of one algorithm" precedent as the Dart/TS geohash encoder
(see memory/dependency_graph.md).
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

SYSTEM_PROMPT = (
    "You are a receipt-understanding engine for Malaysian receipts. The "
    "input is raw OCR text from ONE receipt — a mix of Malay and English, "
    "often with OCR errors (dropped letters, wrong characters, merged "
    "words).\n\n"
    "Respond with ONE JSON object and nothing else — no markdown, no "
    "explanation — with exactly these keys:\n\n"
    '"merchant_name" (string or null): the business name printed on the '
    'receipt, with obvious OCR spelling errors corrected (e.g. "RESTORAN '
    'ANWAR MAU" -> "Restoran Anwar Maju") ONLY when you are confident of '
    "the intended name, normalized to Title Case. Keep legal suffixes "
    "(Sdn Bhd, Enterprise) here if printed. NEVER a phone number, "
    "receipt/invoice number, tax/SST/GST/ROC registration ID, cashier "
    "name, or slogan. null if no business name is readable.\n\n"
    '"merchant_search_queries" (array of 1-3 strings, most specific '
    "first): variants of the merchant name suitable for a Google Places "
    "text search — strip legal suffixes (Sdn Bhd, Trading, Enterprise), "
    "branch codes, and store numbers. Empty array if merchant_name is "
    "null.\n\n"
    '"address_text" (string or null): the vendor\'s street address as '
    "printed on the receipt, cleaned up, or null if none is present. "
    "Never the customer's address.\n\n"
    '"location_clues" (array of strings): short area tokens found on the '
    "receipt that help locate the vendor — neighbourhood (SS2, USJ 10), "
    "mall (Pavilion KL, 1 Utama), city (Petaling Jaya, Kuala Lumpur). "
    "Empty array if none.\n\n"
    '"vendor_category" (string): exactly one of food_and_drink, '
    "groceries, transport, travel, shopping, health_beauty, "
    "entertainment, services, other. Infer from the merchant name AND "
    "the purchased line items — e.g. shampoo + milk + bread means "
    "groceries even if the shop name is unreadable.\n\n"
    '"google_place_types" (array of 1-4 strings): Google Places API '
    "place types matching this vendor, e.g. restaurant, cafe, bakery, "
    "meal_takeaway, fast_food_restaurant, coffee_shop, supermarket, "
    "convenience_store, pharmacy, gas_station, clothing_store, "
    "hair_salon, gym.\n\n"
    '"line_items" (array of objects, one per distinct purchased item): '
    "reconstruct every legible item row, correcting obvious OCR damage "
    '(merged "RM"+digits, a comma misread for a decimal point, '
    "dropped/swapped letters in the item name). Transcribe each price's "
    "digits exactly as printed — never invent or merge digits from a "
    "neighboring line; a single item's price must not exceed the "
    'receipt\'s total. Each object has "name" (string — the item '
    'description, cleaned up), "price" (number or null — the row\'s '
    "printed line total in MYR, never a unit price, no currency "
    'prefix), and "quantity" (number or null — read from a leading '
    'count column printed before the item name, e.g. "3 Teh O Limau '
    'Ais" -> quantity 3, or a trailing multiplier like "2 x"; null '
    "when no quantity is printed, not when the count is 1). Skip "
    "summary rows (subtotal, tax, service charge, rounding, change, "
    "cash/card tendered). Empty array if no item rows are legible.\n\n"
    '"confidence" (object): {"merchant": 0-1, "address": 0-1, '
    '"category": 0-1, "line_items": 0-1} — your confidence in each '
    "extraction.\n\n"
    "If the merchant name is unreadable but an address or line items "
    "are present, set merchant_name to null with a low merchant "
    "confidence and still fill in the address, location clues, and "
    "category."
)


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

    actionable = bool(
        merchant_name or queries or address_text or location_clues or line_items
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
    )


def _build_messages(ocr_text: str) -> list[dict[str, str]]:
    truncated = ocr_text[:MAX_OCR_PROMPT_CHARS]
    return [
        {"role": "system", "content": SYSTEM_PROMPT},
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
    back to weaker heuristics."""
    cfg = resolve_llm_config()

    url = _chat_completions_url(cfg.base_url)
    headers = {"Content-Type": "application/json"}
    if cfg.api_key:
        headers["Authorization"] = f"Bearer {cfg.api_key}"
    messages = _build_messages(ocr_text)

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

    logger.info(
        "LLM understanding ok in %.2fs (model=%s) — merchant=%r "
        "(confidence=%.2f), category=%r (confidence=%.2f), queries=%d, "
        "placeTypes=%d, lineItems=%d",
        elapsed,
        model_used,
        understanding.merchant_name,
        understanding.confidence.merchant,
        understanding.vendor_category,
        understanding.confidence.category,
        len(understanding.merchant_search_queries),
        len(understanding.google_place_types),
        len(understanding.line_items),
    )
    return understanding
