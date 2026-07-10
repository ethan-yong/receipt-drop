import json

import httpx
import pytest
from fastapi.testclient import TestClient

from app.main import app

SECRET = "test-secret"

MCD_JSON = {
    "merchant_name": "McDonald's Pavilion KL",
    "merchant_search_queries": ["McDonald's Pavilion KL", "McDonald's"],
    "address_text": "168 Jalan Bukit Bintang, Kuala Lumpur",
    "location_clues": ["Pavilion KL", "Bukit Bintang", "Kuala Lumpur"],
    "vendor_category": "food_and_drink",
    "google_place_types": ["restaurant", "fast_food_restaurant"],
    "line_items": [{"name": "Big Mac Meal", "price": 17.9, "quantity": 1}],
    "confidence": {"merchant": 0.97, "address": 0.9, "category": 0.99},
}


def _chat_content(text: str) -> str:
    return json.dumps(
        {"model": "test-model", "choices": [{"message": {"content": text}}]}
    )


@pytest.fixture(autouse=True)
def _set_secret(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("OCR_SHARED_SECRET", SECRET)


@pytest.fixture
def client() -> TestClient:
    # `with` runs the app's lifespan (app/main.py's _lifespan) so
    # app.state.http_client exists — POST /ocr now calls the LLM gateway
    # through it in the same request as OCR itself.
    with TestClient(app) as c:
        yield c


def test_health_requires_no_auth(client: TestClient) -> None:
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


def test_ocr_missing_secret_returns_401(client: TestClient) -> None:
    resp = client.post("/ocr", content=b"irrelevant")
    assert resp.status_code == 401
    assert resp.json() == {"error": "unauthorized"}


def test_ocr_wrong_secret_returns_401(client: TestClient) -> None:
    resp = client.post("/ocr", content=b"irrelevant", headers={"X-OCR-Secret": "wrong"})
    assert resp.status_code == 401


def test_ocr_empty_body_returns_400(client: TestClient) -> None:
    resp = client.post("/ocr", content=b"", headers={"X-OCR-Secret": SECRET})
    assert resp.status_code == 400
    assert resp.json() == {"error": "empty_body"}


def test_ocr_invalid_image_returns_400(client: TestClient) -> None:
    resp = client.post(
        "/ocr", content=b"not an image", headers={"X-OCR-Secret": SECRET}
    )
    assert resp.status_code == 400
    assert resp.json() == {"error": "invalid_image"}


def test_ocr_success_returns_text_and_confidence(
    client: TestClient,
    skewed_low_contrast_image_bytes: bytes,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # The real Tesseract binary isn't invoked in unit tests — this exercises
    # the route/preprocessing wiring, not the recognition engine itself.
    from app.ocr_engine import OcrLineResult

    monkeypatch.setattr(
        "app.main.run_ocr_detailed",
        lambda image: ([OcrLineResult(text="TOTAL RM 7.70", height_ratio=0.05)], 0.93),
    )
    # No VLLM_BASE_URL/VLLM_MODEL_NAME configured in this test's environment
    # — the synchronous LLM step fails with server_misconfigured, and the
    # /ocr response must still succeed with the raw OCR fields intact.
    monkeypatch.delenv("VLLM_BASE_URL", raising=False)

    resp = client.post(
        "/ocr",
        content=skewed_low_contrast_image_bytes,
        headers={"X-OCR-Secret": SECRET, "Content-Type": "image/png"},
    )

    assert resp.status_code == 200
    body = resp.json()
    assert body["text"] == "TOTAL RM 7.70"
    assert body["confidence"] == pytest.approx(0.93)
    assert body["lines"] == [{"text": "TOTAL RM 7.70", "height_ratio": 0.05}]
    assert body["understanding"] is None
    assert body["understanding_error"] == "server_misconfigured"


def test_ocr_success_includes_llm_understanding(
    client: TestClient,
    skewed_low_contrast_image_bytes: bytes,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.ocr_engine import OcrLineResult

    monkeypatch.setattr(
        "app.main.run_ocr_detailed",
        lambda image: (
            [OcrLineResult(text="MCDONALD'S PAVILION KL", height_ratio=0.08)],
            0.93,
        ),
    )
    monkeypatch.setenv("VLLM_BASE_URL", "http://gateway.local:31180")
    monkeypatch.setenv("VLLM_MODEL_NAME", "test-model")

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=_chat_content(json.dumps(MCD_JSON)))

    app.state.http_client = httpx.AsyncClient(transport=httpx.MockTransport(handler))

    resp = client.post(
        "/ocr",
        content=skewed_low_contrast_image_bytes,
        headers={"X-OCR-Secret": SECRET, "Content-Type": "image/png"},
    )

    assert resp.status_code == 200
    body = resp.json()
    assert body["text"] == "MCDONALD'S PAVILION KL"
    assert body["understanding_error"] is None
    understanding = body["understanding"]
    assert understanding["merchant_name"] == "McDonald's Pavilion KL"
    assert understanding["vendor_category"] == "food_and_drink"
    assert understanding["line_items"] == [
        {"name": "Big Mac Meal", "price": 17.9, "quantity": 1}
    ]


def test_ocr_llm_failure_still_returns_raw_ocr(
    client: TestClient,
    skewed_low_contrast_image_bytes: bytes,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.ocr_engine import OcrLineResult

    monkeypatch.setattr(
        "app.main.run_ocr_detailed",
        lambda image: ([OcrLineResult(text="TOTAL RM 7.70", height_ratio=0.05)], 0.93),
    )
    monkeypatch.setenv("VLLM_BASE_URL", "http://gateway.local:31180")
    monkeypatch.setenv("VLLM_MODEL_NAME", "test-model")

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(503, text="upstream down")

    app.state.http_client = httpx.AsyncClient(transport=httpx.MockTransport(handler))

    resp = client.post(
        "/ocr",
        content=skewed_low_contrast_image_bytes,
        headers={"X-OCR-Secret": SECRET, "Content-Type": "image/png"},
    )

    assert resp.status_code == 200
    body = resp.json()
    assert body["text"] == "TOTAL RM 7.70"
    assert body["confidence"] == pytest.approx(0.93)
    assert body["understanding"] is None
    assert body["understanding_error"] == "llm_http_503"


def test_ocr_no_text_recognized_skips_llm_call(
    client: TestClient,
    skewed_low_contrast_image_bytes: bytes,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(
        "app.main.run_ocr_detailed",
        lambda image: ([], 0.0),
    )

    calls = 0

    async def _fail_if_called(*args: object, **kwargs: object) -> None:
        nonlocal calls
        calls += 1
        raise AssertionError("LLM should not be called when OCR found no text")

    monkeypatch.setattr("app.main.call_receipt_understanding", _fail_if_called)

    resp = client.post(
        "/ocr",
        content=skewed_low_contrast_image_bytes,
        headers={"X-OCR-Secret": SECRET, "Content-Type": "image/png"},
    )

    assert resp.status_code == 200
    body = resp.json()
    assert body["text"] == ""
    assert body["understanding"] is None
    assert body["understanding_error"] is None
    assert calls == 0
