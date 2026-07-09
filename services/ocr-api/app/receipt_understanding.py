"""LLM receipt-understanding step: turns raw OCR text into structured
merchant info (corrected name, search queries, address clues, category,
Google Places types, confidences) for `enrich-transaction`'s Places matching.

Calls a self-hosted OpenAI-compatible gateway (LiteLLM/vLLM), same one probed
by scripts/inspect_llm_endpoint.py — VLLM_BASE_URL/VLLM_API_KEY/
VLLM_MODEL_NAME/VLLM_REASONING_EFFORT, read from the root .env via
app/__main__.py's _load_root_dotenv().

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

import httpx
from pydantic import BaseModel

logger = logging.getLogger("ocr_api.receipt_understanding")

LLM_TIMEOUT_SECONDS = 25.0
MAX_OCR_PROMPT_CHARS = 6_000
LLM_MAX_TOKENS = 700
MAX_MERCHANT_SEARCH_QUERIES = 3

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
    '"confidence" (object): {"merchant": 0-1, "address": 0-1, '
    '"category": 0-1} — your confidence in each extraction.\n\n'
    "If the merchant name is unreadable but an address or line items "
    "are present, set merchant_name to null with a low merchant "
    "confidence and still fill in the address, location clues, and "
    "category."
)


class ReceiptUnderstandingConfidence(BaseModel):
    merchant: float
    address: float
    category: float


class ReceiptUnderstandingRequest(BaseModel):
    ocr_text: str


class ReceiptUnderstandingResponse(BaseModel):
    merchant_name: str | None
    merchant_search_queries: list[str]
    address_text: str | None
    location_clues: list[str]
    vendor_category: str | None
    google_place_types: list[str]
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

    actionable = bool(merchant_name or queries or address_text or location_clues)
    if not actionable:
        return None

    return ReceiptUnderstandingResponse(
        merchant_name=merchant_name,
        merchant_search_queries=queries,
        address_text=address_text,
        location_clues=location_clues,
        vendor_category=vendor_category,
        google_place_types=place_types,
        confidence=ReceiptUnderstandingConfidence(
            merchant=_clamp01(confidence_obj.get("merchant")),
            address=_clamp01(confidence_obj.get("address")),
            category=_clamp01(confidence_obj.get("category")),
        ),
    )


def _build_messages(ocr_text: str) -> list[dict[str, str]]:
    truncated = ocr_text[:MAX_OCR_PROMPT_CHARS]
    return [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": truncated},
    ]


async def call_receipt_understanding(
    ocr_text: str, *, http_client: httpx.AsyncClient
) -> ReceiptUnderstandingResponse:
    """Calls the LLM gateway and returns a validated understanding, or raises
    [ReceiptUnderstandingError]. No retry beyond one narrow response_format
    fallback on HTTP 400 — every other failure propagates immediately so the
    caller (enrich-transaction) fails the enrichment rather than falling
    back to weaker heuristics."""
    base_url = os.environ.get("VLLM_BASE_URL", "").strip()
    model_name = os.environ.get("VLLM_MODEL_NAME", "").strip()
    api_key = os.environ.get("VLLM_API_KEY", "").strip() or None
    reasoning_effort = os.environ.get("VLLM_REASONING_EFFORT", "").strip() or None

    if not base_url or not model_name:
        raise ReceiptUnderstandingError(
            "server_misconfigured",
            "VLLM_BASE_URL/VLLM_MODEL_NAME not set",
        )

    url = _chat_completions_url(base_url)
    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    messages = _build_messages(ocr_text)

    def _body(with_response_format: bool) -> dict[str, object]:
        body: dict[str, object] = {
            "model": model_name,
            "messages": messages,
            "temperature": 0,
            "max_tokens": LLM_MAX_TOKENS,
        }
        if with_response_format:
            body["response_format"] = {"type": "json_object"}
        if reasoning_effort:
            body["reasoning_effort"] = reasoning_effort
        return body

    start = time.perf_counter()
    logger.info(
        "calling LLM gateway model=%s ocrTextChars=%d", model_name, len(ocr_text)
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
        model_used = payload.get("model", model_name)
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
        "(confidence=%.2f), category=%r (confidence=%.2f), queries=%d, placeTypes=%d",
        elapsed,
        model_used,
        understanding.merchant_name,
        understanding.confidence.merchant,
        understanding.vendor_category,
        understanding.confidence.category,
        len(understanding.merchant_search_queries),
        len(understanding.google_place_types),
    )
    return understanding
