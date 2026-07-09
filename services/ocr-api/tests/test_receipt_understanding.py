import json

import httpx
import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.receipt_understanding import (
    ReceiptUnderstandingError,
    call_receipt_understanding,
    parse_receipt_understanding,
)

SECRET = "test-secret"

MCD_JSON = {
    "merchant_name": "McDonald's Pavilion KL",
    "merchant_search_queries": ["McDonald's Pavilion KL", "McDonald's"],
    "address_text": "168 Jalan Bukit Bintang, Kuala Lumpur",
    "location_clues": ["Pavilion KL", "Bukit Bintang", "Kuala Lumpur"],
    "vendor_category": "food_and_drink",
    "google_place_types": ["restaurant", "fast_food_restaurant"],
    "confidence": {"merchant": 0.97, "address": 0.9, "category": 0.99},
}


def _chat_content(text: str) -> str:
    return json.dumps(
        {"model": "test-model", "choices": [{"message": {"content": text}}]}
    )


# ---------------------------------------------------------------------------
# parse_receipt_understanding
# ---------------------------------------------------------------------------


def test_parses_clear_restaurant_receipt() -> None:
    u = parse_receipt_understanding(json.dumps(MCD_JSON))
    assert u is not None
    assert u.merchant_name == "McDonald's Pavilion KL"
    assert u.vendor_category == "food_and_drink"
    assert u.google_place_types == ["restaurant", "fast_food_restaurant"]
    assert u.confidence.merchant == pytest.approx(0.97)


def test_ocr_corruption_corrected_name_parses() -> None:
    payload = {
        "merchant_name": "Restoran Anwar Maju Sdn Bhd",
        "merchant_search_queries": ["Restoran Anwar Maju", "Anwar Maju"],
        "address_text": "Lot 12 Jalan SS2/24, Petaling Jaya",
        "location_clues": ["SS2", "Petaling Jaya"],
        "vendor_category": "food_and_drink",
        "google_place_types": ["restaurant"],
        "confidence": {"merchant": 0.85, "address": 0.8, "category": 0.95},
    }
    u = parse_receipt_understanding(json.dumps(payload))
    assert u is not None
    assert u.merchant_name == "Restoran Anwar Maju Sdn Bhd"
    assert u.merchant_search_queries == ["Restoran Anwar Maju", "Anwar Maju"]


def test_grocery_invalid_place_types_filtered() -> None:
    payload = {
        "merchant_name": "Lotus's Kepong",
        "merchant_search_queries": ["Lotus's Kepong"],
        "address_text": None,
        "location_clues": ["Kepong"],
        "vendor_category": "groceries",
        "google_place_types": ["hypermarket", "supermarket"],
        "confidence": {"merchant": 0.9, "address": 0.1, "category": 0.98},
    }
    u = parse_receipt_understanding(json.dumps(payload))
    assert u is not None
    assert u.google_place_types == ["supermarket"]


def test_missing_merchant_but_address_still_parses() -> None:
    payload = {
        "merchant_name": None,
        "merchant_search_queries": [],
        "address_text": "Jalan SS15/4, Subang Jaya",
        "location_clues": ["SS15", "Subang Jaya"],
        "vendor_category": "food_and_drink",
        "google_place_types": ["restaurant"],
        "confidence": {"merchant": 0.1, "address": 0.85, "category": 0.9},
    }
    u = parse_receipt_understanding(json.dumps(payload))
    assert u is not None
    assert u.merchant_name is None
    assert u.confidence.merchant == pytest.approx(0.1)


def test_nothing_actionable_returns_none() -> None:
    payload = {
        "merchant_name": None,
        "merchant_search_queries": [],
        "address_text": None,
        "location_clues": [],
        "vendor_category": "other",
        "google_place_types": [],
        "confidence": {"merchant": 0, "address": 0, "category": 0.2},
    }
    assert parse_receipt_understanding(json.dumps(payload)) is None


def test_totally_unparseable_returns_none() -> None:
    assert parse_receipt_understanding("I could not read this receipt.") is None
    assert parse_receipt_understanding("") is None
    assert parse_receipt_understanding("{not json") is None


def test_strips_markdown_fence_and_think_block() -> None:
    raw = "<think>reasoning...</think>```json\n" + json.dumps(MCD_JSON) + "\n```"
    u = parse_receipt_understanding(raw)
    assert u is not None
    assert u.merchant_name == "McDonald's Pavilion KL"


def test_out_of_range_confidence_clamped() -> None:
    payload = {
        "merchant_name": "Kedai Ali",
        "merchant_search_queries": ["Kedai Ali"],
        "address_text": None,
        "location_clues": [],
        "vendor_category": "groceries",
        "google_place_types": [],
        "confidence": {"merchant": 1.7, "address": -0.4, "category": "high"},
    }
    u = parse_receipt_understanding(json.dumps(payload))
    assert u is not None
    assert u.confidence.merchant == 1.0
    assert u.confidence.address == 0.0
    assert u.confidence.category == 0.0


def test_off_vocabulary_category_is_nulled() -> None:
    payload = {
        "merchant_name": "Kedai Ali",
        "merchant_search_queries": ["Kedai Ali"],
        "address_text": None,
        "location_clues": [],
        "vendor_category": "restaurant_and_bar",
        "google_place_types": [],
        "confidence": {},
    }
    u = parse_receipt_understanding(json.dumps(payload))
    assert u is not None
    assert u.vendor_category is None


def test_more_than_three_queries_capped() -> None:
    payload = {
        "merchant_name": "Restoran Lima Nama",
        "merchant_search_queries": ["One", "Two", "Three", "Four", "Five"],
        "address_text": None,
        "location_clues": [],
        "vendor_category": "food_and_drink",
        "google_place_types": [],
        "confidence": {},
    }
    u = parse_receipt_understanding(json.dumps(payload))
    assert u is not None
    assert len(u.merchant_search_queries) == 3


# ---------------------------------------------------------------------------
# call_receipt_understanding (httpx.MockTransport — no real network)
# ---------------------------------------------------------------------------


@pytest.fixture(autouse=True)
def _set_llm_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("VLLM_BASE_URL", "http://gateway.local:31180")
    monkeypatch.setenv("VLLM_MODEL_NAME", "test-model")
    monkeypatch.setenv("VLLM_API_KEY", "sk-test")
    monkeypatch.delenv("VLLM_REASONING_EFFORT", raising=False)


async def test_call_returns_validated_understanding() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url == "http://gateway.local:31180/v1/chat/completions"
        return httpx.Response(200, content=_chat_content(json.dumps(MCD_JSON)))

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        result = await call_receipt_understanding("MCDONALD'S...", http_client=client)
    assert result.merchant_name == "McDonald's Pavilion KL"


async def test_call_retries_without_response_format_on_400() -> None:
    calls: list[dict] = []

    def handler(request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        calls.append(body)
        if len(calls) == 1:
            assert "response_format" in body
            return httpx.Response(400, text="response_format unsupported")
        assert "response_format" not in body
        return httpx.Response(200, content=_chat_content(json.dumps(MCD_JSON)))

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        result = await call_receipt_understanding("receipt text", http_client=client)
    assert len(calls) == 2
    assert result.merchant_name == "McDonald's Pavilion KL"


async def test_call_surfaces_http_errors_without_retry() -> None:
    calls = 0

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        return httpx.Response(503, text="boom")

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        with pytest.raises(ReceiptUnderstandingError) as exc_info:
            await call_receipt_understanding("receipt text", http_client=client)
    assert exc_info.value.code == "llm_http_503"
    assert calls == 1


async def test_call_flags_unparseable_content() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=_chat_content("I cannot read this receipt."))

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        with pytest.raises(ReceiptUnderstandingError) as exc_info:
            await call_receipt_understanding("receipt text", http_client=client)
    assert exc_info.value.code == "llm_unparseable_content"


async def test_call_missing_config_raises_server_misconfigured(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("VLLM_BASE_URL", raising=False)
    async with httpx.AsyncClient() as client:
        with pytest.raises(ReceiptUnderstandingError) as exc_info:
            await call_receipt_understanding("receipt text", http_client=client)
    assert exc_info.value.code == "server_misconfigured"


# ---------------------------------------------------------------------------
# POST /understand (FastAPI route + auth + error-status mapping)
# ---------------------------------------------------------------------------


@pytest.fixture(autouse=True)
def _set_secret(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("OCR_SHARED_SECRET", SECRET)


@pytest.fixture
def client() -> TestClient:
    with TestClient(app) as c:
        yield c


def test_understand_missing_secret_returns_401(client: TestClient) -> None:
    resp = client.post("/understand", json={"ocr_text": "some receipt"})
    assert resp.status_code == 401


def test_understand_empty_text_returns_400(client: TestClient) -> None:
    resp = client.post(
        "/understand", json={"ocr_text": "  "}, headers={"X-OCR-Secret": SECRET}
    )
    assert resp.status_code == 400
    assert resp.json() == {"error": "empty_ocr_text"}


def test_understand_success(client: TestClient) -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=_chat_content(json.dumps(MCD_JSON)))

    app.state.http_client = httpx.AsyncClient(transport=httpx.MockTransport(handler))

    resp = client.post(
        "/understand",
        json={"ocr_text": "MCDONALD'S PAVILION KL..."},
        headers={"X-OCR-Secret": SECRET},
    )
    assert resp.status_code == 200
    assert resp.json()["merchant_name"] == "McDonald's Pavilion KL"


def test_understand_llm_error_maps_to_502(client: TestClient) -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(503, text="upstream down")

    app.state.http_client = httpx.AsyncClient(transport=httpx.MockTransport(handler))

    resp = client.post(
        "/understand",
        json={"ocr_text": "receipt text"},
        headers={"X-OCR-Secret": SECRET},
    )
    assert resp.status_code == 502
    assert resp.json() == {"error": "llm_http_503"}


def test_understand_missing_config_maps_to_500(
    client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.delenv("VLLM_BASE_URL", raising=False)
    resp = client.post(
        "/understand",
        json={"ocr_text": "receipt text"},
        headers={"X-OCR-Secret": SECRET},
    )
    assert resp.status_code == 500
    assert resp.json() == {"error": "server_misconfigured"}
