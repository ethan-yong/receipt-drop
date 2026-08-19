import json

import httpx
import pytest
from fastapi.testclient import TestClient

from ocr_api.main import app
from ocr_api.payment_notification_understanding import (
    call_payment_notification_understanding,
    parse_payment_notification_understanding,
)

SECRET = "test-secret"


@pytest.fixture(autouse=True)
def _set_llm_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("LLM_PROVIDER", "vllm")
    monkeypatch.setenv("VLLM_BASE_URL", "http://gateway.local:31180")
    monkeypatch.setenv("VLLM_MODEL_NAME", "test-model")


def _chat_content(text: str) -> str:
    return json.dumps(
        {"model": "test-model", "choices": [{"message": {"content": text}}]}
    )


# ---------------------------------------------------------------------------
# parse_payment_notification_understanding — payment / transfer_out /
# transfer_in / DuitNow / missing fields / ambiguous / malformed
# ---------------------------------------------------------------------------


def test_parses_payment() -> None:
    payload = {
        "transaction_type": "payment",
        "merchant": "Starbucks",
        "counterparty": None,
        "amount": 18.50,
        "currency": "MYR",
        "confidence": 0.95,
    }
    u = parse_payment_notification_understanding(json.dumps(payload))
    assert u is not None
    assert u.transaction_type == "payment"
    assert u.merchant == "Starbucks"
    assert u.counterparty is None
    assert u.amount == pytest.approx(18.50)
    assert u.currency == "MYR"


def test_parses_transfer_out() -> None:
    payload = {
        "transaction_type": "transfer_out",
        "merchant": None,
        "counterparty": "John",
        "amount": 100.0,
        "currency": "MYR",
        "confidence": 0.9,
    }
    u = parse_payment_notification_understanding(json.dumps(payload))
    assert u is not None
    assert u.transaction_type == "transfer_out"
    assert u.counterparty == "John"
    assert u.merchant is None
    assert u.amount == pytest.approx(100.0)


def test_parses_transfer_in() -> None:
    payload = {
        "transaction_type": "transfer_in",
        "merchant": None,
        "counterparty": "Sarah",
        "amount": 500.0,
        "currency": "MYR",
        "confidence": 0.92,
    }
    u = parse_payment_notification_understanding(json.dumps(payload))
    assert u is not None
    assert u.transaction_type == "transfer_in"
    assert u.counterparty == "Sarah"


def test_parses_duitnow_transfer_out() -> None:
    payload = {
        "transaction_type": "transfer_out",
        "counterparty": "Ali",
        "amount": 50.0,
        "currency": "MYR",
        "confidence": 0.88,
    }
    u = parse_payment_notification_understanding(json.dumps(payload))
    assert u is not None
    assert u.transaction_type == "transfer_out"
    assert u.counterparty == "Ali"
    assert u.amount == pytest.approx(50.0)


def test_merchant_missing_still_parses_with_null_merchant() -> None:
    payload = {
        "transaction_type": "payment",
        "merchant": None,
        "amount": 20.0,
        "currency": "MYR",
        "confidence": 0.4,
    }
    u = parse_payment_notification_understanding(json.dumps(payload))
    assert u is not None
    assert u.transaction_type == "payment"
    assert u.merchant is None
    assert u.amount == pytest.approx(20.0)


def test_amount_missing_downgrades_to_unknown() -> None:
    """A typed result with no amount must never be handed back typed —
    downgraded to unknown so the caller never shows an overlay for it."""
    payload = {
        "transaction_type": "payment",
        "merchant": "Starbucks",
        "amount": None,
        "currency": "MYR",
        "confidence": 0.8,
    }
    u = parse_payment_notification_understanding(json.dumps(payload))
    assert u is not None
    assert u.transaction_type == "unknown"
    assert u.amount is None
    assert u.merchant is None


def test_ambiguous_transaction_stays_unknown() -> None:
    payload = {
        "transaction_type": "unknown",
        "merchant": None,
        "counterparty": None,
        "amount": None,
        "currency": "MYR",
        "confidence": 0.1,
    }
    u = parse_payment_notification_understanding(json.dumps(payload))
    assert u is not None
    assert u.transaction_type == "unknown"
    assert u.amount is None


def test_off_vocabulary_transaction_type_downgrades_to_unknown() -> None:
    payload = {
        "transaction_type": "refund",
        "amount": 10.0,
        "currency": "MYR",
        "confidence": 0.5,
    }
    u = parse_payment_notification_understanding(json.dumps(payload))
    assert u is not None
    assert u.transaction_type == "unknown"


def test_negative_or_zero_amount_treated_as_no_amount() -> None:
    payload = {
        "transaction_type": "payment",
        "merchant": "Starbucks",
        "amount": 0,
        "currency": "MYR",
        "confidence": 0.9,
    }
    u = parse_payment_notification_understanding(json.dumps(payload))
    assert u is not None
    assert u.transaction_type == "unknown"
    assert u.amount is None


def test_merchant_dropped_for_transfer_type() -> None:
    """merchant only applies to `payment` — a transfer response shouldn't
    carry a stray merchant value even if the model mistakenly included one."""
    payload = {
        "transaction_type": "transfer_out",
        "merchant": "Should not appear",
        "counterparty": "John",
        "amount": 100.0,
        "currency": "MYR",
        "confidence": 0.9,
    }
    u = parse_payment_notification_understanding(json.dumps(payload))
    assert u is not None
    assert u.merchant is None
    assert u.counterparty == "John"


def test_counterparty_dropped_for_payment_type() -> None:
    payload = {
        "transaction_type": "payment",
        "merchant": "Starbucks",
        "counterparty": "Should not appear",
        "amount": 18.5,
        "currency": "MYR",
        "confidence": 0.9,
    }
    u = parse_payment_notification_understanding(json.dumps(payload))
    assert u is not None
    assert u.counterparty is None
    assert u.merchant == "Starbucks"


def test_explicit_non_myr_currency_is_honored() -> None:
    payload = {
        "transaction_type": "payment",
        "merchant": "Amazon",
        "amount": 20.0,
        "currency": "USD",
        "confidence": 0.7,
    }
    u = parse_payment_notification_understanding(json.dumps(payload))
    assert u is not None
    assert u.currency == "USD"


def test_missing_currency_defaults_to_myr() -> None:
    payload = {"transaction_type": "payment", "merchant": "Starbucks", "amount": 18.5}
    u = parse_payment_notification_understanding(json.dumps(payload))
    assert u is not None
    assert u.currency == "MYR"


def test_low_confidence_still_parses_but_confidence_reflects_it() -> None:
    payload = {
        "transaction_type": "payment",
        "merchant": "Somewhere",
        "amount": 5.0,
        "currency": "MYR",
        "confidence": 0.05,
    }
    u = parse_payment_notification_understanding(json.dumps(payload))
    assert u is not None
    assert u.confidence == pytest.approx(0.05)


def test_malformed_llm_output_returns_none() -> None:
    assert parse_payment_notification_understanding("not json at all") is None


def test_missing_required_transaction_type_field_defaults_unknown() -> None:
    payload = {"amount": 18.5, "merchant": "Starbucks"}
    u = parse_payment_notification_understanding(json.dumps(payload))
    assert u is not None
    assert u.transaction_type == "unknown"


def test_non_dict_json_returns_none() -> None:
    assert parse_payment_notification_understanding("[1, 2, 3]") is None


# ---------------------------------------------------------------------------
# call_payment_notification_understanding — gateway call + non-financial /
# unknown-package inputs feed through the same LLM path (no local filtering
# happens inside this module — that's the native heuristic's job upstream)
# ---------------------------------------------------------------------------


async def test_call_success() -> None:
    payload = {
        "transaction_type": "payment",
        "merchant": "Starbucks",
        "amount": 18.5,
        "currency": "MYR",
        "confidence": 0.95,
    }

    def handler(request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        assert "RM18.50" in body["messages"][1]["content"]
        return httpx.Response(200, content=_chat_content(json.dumps(payload)))

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        result = await call_payment_notification_understanding(
            "RM18.50 paid to Starbucks",
            "com.google.android.apps.walletnfcrel",
            "2026-08-17T10:00:00Z",
            http_client=client,
        )
    assert result.transaction_type == "payment"
    assert result.merchant == "Starbucks"


async def test_call_unknown_source_package_still_processed() -> None:
    """The Kotlin-side heuristic decides whether to call this at all —
    the server itself never gates on source_package."""
    payload = {"transaction_type": "unknown", "amount": None, "confidence": 0.1}

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=_chat_content(json.dumps(payload)))

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        result = await call_payment_notification_understanding(
            "Your RM500 phone bill is due tomorrow",
            "com.totally.unknown.bank.app",
            None,
            http_client=client,
        )
    assert result.transaction_type == "unknown"


# ---------------------------------------------------------------------------
# POST /understand-payment-notification (route + auth + non-financial input)
# ---------------------------------------------------------------------------


@pytest.fixture(autouse=True)
def _set_secret(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("OCR_SHARED_SECRET", SECRET)


@pytest.fixture
def client() -> TestClient:
    with TestClient(app) as c:
        yield c


def test_route_missing_secret_returns_401(client: TestClient) -> None:
    resp = client.post(
        "/understand-payment-notification", json={"notification_text": "RM18.50 paid"}
    )
    assert resp.status_code == 401


def test_route_empty_text_returns_400(client: TestClient) -> None:
    resp = client.post(
        "/understand-payment-notification",
        json={"notification_text": "  "},
        headers={"X-OCR-Secret": SECRET},
    )
    assert resp.status_code == 400
    assert resp.json() == {"error": "empty_notification_text"}


def test_route_success(client: TestClient) -> None:
    payload = {
        "transaction_type": "transfer_out",
        "counterparty": "John",
        "amount": 100.0,
        "currency": "MYR",
        "confidence": 0.9,
    }

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=_chat_content(json.dumps(payload)))

    app.state.http_client = httpx.AsyncClient(transport=httpx.MockTransport(handler))

    resp = client.post(
        "/understand-payment-notification",
        json={
            "notification_text": "RM100 transferred to John",
            "source_package": "my.com.maybank2u.life",
        },
        headers={"X-OCR-Secret": SECRET},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["transaction_type"] == "transfer_out"
    assert body["counterparty"] == "John"
    assert body["amount"] == 100.0


def test_route_non_financial_notification_yields_unknown(client: TestClient) -> None:
    """Not a false-positive test at the parser layer (that's the native
    heuristic's job) — this confirms the LLM pipeline itself degrades an
    obviously non-transactional notification to unknown rather than
    fabricating a transaction, as a second line of defense."""
    payload = {"transaction_type": "unknown", "amount": None, "confidence": 0.05}

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=_chat_content(json.dumps(payload)))

    app.state.http_client = httpx.AsyncClient(transport=httpx.MockTransport(handler))

    resp = client.post(
        "/understand-payment-notification",
        json={"notification_text": "RM is mentioned in a promotional notification"},
        headers={"X-OCR-Secret": SECRET},
    )
    assert resp.status_code == 200
    assert resp.json()["transaction_type"] == "unknown"


def test_route_llm_timeout_returns_504(client: TestClient) -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.TimeoutException("timed out", request=request)

    app.state.http_client = httpx.AsyncClient(transport=httpx.MockTransport(handler))

    resp = client.post(
        "/understand-payment-notification",
        json={"notification_text": "RM18.50 paid to Starbucks"},
        headers={"X-OCR-Secret": SECRET},
    )
    assert resp.status_code == 504
    assert resp.json() == {"error": "llm_timeout"}


def test_route_malformed_llm_output_returns_502(client: TestClient) -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=_chat_content("not json"))

    app.state.http_client = httpx.AsyncClient(transport=httpx.MockTransport(handler))

    resp = client.post(
        "/understand-payment-notification",
        json={"notification_text": "RM18.50 paid to Starbucks"},
        headers={"X-OCR-Secret": SECRET},
    )
    assert resp.status_code == 502
    assert resp.json() == {"error": "llm_unparseable_content"}
