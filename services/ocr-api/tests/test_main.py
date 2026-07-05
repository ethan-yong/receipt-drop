import pytest
from fastapi.testclient import TestClient

from app.main import app

SECRET = "test-secret"


@pytest.fixture(autouse=True)
def _set_secret(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("OCR_SHARED_SECRET", SECRET)


@pytest.fixture
def client() -> TestClient:
    return TestClient(app)


def test_health_requires_no_auth(client: TestClient) -> None:
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


def test_ocr_missing_secret_returns_401(client: TestClient) -> None:
    resp = client.post("/ocr", content=b"irrelevant")
    assert resp.status_code == 401
    assert resp.json() == {"error": "unauthorized"}


def test_ocr_wrong_secret_returns_401(client: TestClient) -> None:
    resp = client.post(
        "/ocr", content=b"irrelevant", headers={"X-OCR-Secret": "wrong"}
    )
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
    monkeypatch.setattr(
        "app.main.run_ocr", lambda image: ("TOTAL RM 7.70", 0.93)
    )

    resp = client.post(
        "/ocr",
        content=skewed_low_contrast_image_bytes,
        headers={"X-OCR-Secret": SECRET, "Content-Type": "image/png"},
    )

    assert resp.status_code == 200
    body = resp.json()
    assert body["text"] == "TOTAL RM 7.70"
    assert body["confidence"] == pytest.approx(0.93)
