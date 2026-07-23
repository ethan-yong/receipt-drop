import json

import httpx
import pytest
from fastapi.testclient import TestClient

from ocr_api.main import app
from ocr_api.ocr_engine import OcrLineResult
from ocr_api.receipt_understanding import (
    ReceiptUnderstandingError,
    _apply_cleanup_guard,
    _build_cleanup_line_block,
    _coerce_cleanup_fields,
    _select_cleanup_lines,
    call_receipt_understanding,
    edit_distance_ratio,
    parse_receipt_understanding,
    resolve_llm_config,
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


def test_line_items_parsed_and_coerced() -> None:
    payload = {
        "merchant_name": "Sample Store",
        "merchant_search_queries": ["Sample Store"],
        "address_text": None,
        "location_clues": [],
        "vendor_category": "groceries",
        "google_place_types": [],
        "line_items": [
            {"name": "Milk", "price": 4.5, "quantity": 1},
            {"name": "Bread", "price": "3.20", "quantity": None},
            {"name": "Eggs", "price": None, "quantity": 2},
        ],
        "confidence": {
            "merchant": 0.9,
            "address": 0.1,
            "category": 0.9,
            "line_items": 0.8,
        },
    }
    u = parse_receipt_understanding(json.dumps(payload))
    assert u is not None
    assert len(u.line_items) == 3
    assert u.line_items[0].name == "Milk"
    assert u.line_items[0].price == pytest.approx(4.5)
    assert u.line_items[1].price == pytest.approx(3.2)
    assert u.line_items[2].price is None
    assert u.line_items[2].quantity == pytest.approx(2)
    assert u.confidence.line_items == pytest.approx(0.8)


def test_line_items_malformed_entries_dropped() -> None:
    payload = {
        "merchant_name": "Sample Store",
        "merchant_search_queries": [],
        "address_text": None,
        "location_clues": [],
        "vendor_category": "groceries",
        "google_place_types": [],
        "line_items": [
            {"name": "Milk", "price": 4.5},
            {"name": None, "price": 9.9},  # no name -> dropped
            "not a dict",  # dropped
            # unparseable price kept, price None
            {"name": "Bad Price", "price": "free"},
            {"name": "Negative", "price": -5},  # negative price coerced to None
        ],
        "confidence": {},
    }
    u = parse_receipt_understanding(json.dumps(payload))
    assert u is not None
    names = [it.name for it in u.line_items]
    assert names == ["Milk", "Bad Price", "Negative"]
    assert u.line_items[1].price is None
    assert u.line_items[2].price is None


def test_line_items_capped_at_max() -> None:
    payload = {
        "merchant_name": "Big Receipt",
        "merchant_search_queries": [],
        "address_text": None,
        "location_clues": [],
        "vendor_category": "groceries",
        "google_place_types": [],
        "line_items": [{"name": f"Item {i}", "price": 1.0} for i in range(60)],
        "confidence": {},
    }
    u = parse_receipt_understanding(json.dumps(payload))
    assert u is not None
    assert len(u.line_items) == 40


def test_actionable_via_line_items_only() -> None:
    payload = {
        "merchant_name": None,
        "merchant_search_queries": [],
        "address_text": None,
        "location_clues": [],
        "vendor_category": None,
        "google_place_types": [],
        "line_items": [{"name": "Mystery Item", "price": 5.0}],
        "confidence": {},
    }
    u = parse_receipt_understanding(json.dumps(payload))
    assert u is not None
    assert len(u.line_items) == 1


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
# OCR cleanup: pure helpers (edit_distance_ratio, guard, line selection)
# ---------------------------------------------------------------------------


def test_edit_distance_ratio_zero_for_identical_lines() -> None:
    assert edit_distance_ratio("TOTAL RM7.70", "TOTAL RM7.70") == 0.0


def test_edit_distance_ratio_low_for_single_char_confusion() -> None:
    # "T0TAL" -> "TOTAL": one substitution over 5 chars.
    ratio = edit_distance_ratio("T0TAL", "TOTAL")
    assert 0.0 < ratio <= 0.25


def test_edit_distance_ratio_high_for_rewritten_line() -> None:
    ratio = edit_distance_ratio("RESTORAN AME", "Restoran Anwar Maju Sdn Bhd")
    assert ratio > 0.5


def test_edit_distance_ratio_bounded_for_empty_strings() -> None:
    assert edit_distance_ratio("", "") == 0.0
    assert edit_distance_ratio("abc", "") == 1.0


def test_apply_cleanup_guard_accepts_low_distance_correction() -> None:
    cleaned, corrections = _apply_cleanup_guard(
        ["T0TAL RM7.70", "Kedai Ali"], ["TOTAL RM7.70", "Kedai Ali"]
    )
    assert cleaned == ["TOTAL RM7.70", "Kedai Ali"]
    assert len(corrections) == 1
    assert corrections[0].line_index == 0
    assert corrections[0].original == "T0TAL RM7.70"
    assert corrections[0].corrected == "TOTAL RM7.70"


def test_apply_cleanup_guard_reverts_high_distance_line_only(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("LLM_CLEANUP_EDIT_DISTANCE_THRESHOLD", "0.3")
    cleaned, corrections = _apply_cleanup_guard(
        ["T0TAL RM7.70", "RESTORAN AME"],
        ["TOTAL RM7.70", "Restoran Anwar Maju Sdn Bhd"],
    )
    # Line 0's low-distance fix is kept; line 1's high-distance rewrite is
    # discarded independently — one bad line doesn't sink the whole pass.
    assert cleaned == ["TOTAL RM7.70", "RESTORAN AME"]
    assert len(corrections) == 1
    assert corrections[0].line_index == 0


def test_apply_cleanup_guard_noop_when_lines_identical() -> None:
    cleaned, corrections = _apply_cleanup_guard(
        ["Kedai Ali", "TOTAL RM7.70"], ["Kedai Ali", "TOTAL RM7.70"]
    )
    assert cleaned == ["Kedai Ali", "TOTAL RM7.70"]
    assert corrections == []


def test_apply_cleanup_guard_rejects_wrong_length_candidate() -> None:
    cleaned, corrections = _apply_cleanup_guard(["A", "B"], ["A"])
    assert cleaned is None
    assert corrections == []


def test_apply_cleanup_guard_rejects_non_list_candidate() -> None:
    cleaned, corrections = _apply_cleanup_guard(["A", "B"], "not a list")
    assert cleaned is None
    assert corrections == []


def test_apply_cleanup_guard_rejects_non_string_entries() -> None:
    cleaned, corrections = _apply_cleanup_guard(["A", "B"], ["A", 123])
    # Entry 1 isn't a usable string -> treated as "no correction", original kept.
    assert cleaned == ["A", "B"]
    assert corrections == []


def test_coerce_cleanup_fields_none_when_no_cleanup_attempted() -> None:
    cleaned, text, corrections = _coerce_cleanup_fields(["X"], cleanup_lines=None)
    assert cleaned is None
    assert text is None
    assert corrections == []


def test_coerce_cleanup_fields_builds_joined_text() -> None:
    lines = [
        OcrLineResult(text="T0TAL RM7.70", height_ratio=0.05, confidence=0.4),
        OcrLineResult(text="Kedai Ali", height_ratio=0.1, confidence=0.9),
    ]
    cleaned, text, corrections = _coerce_cleanup_fields(
        ["TOTAL RM7.70", "Kedai Ali"], cleanup_lines=lines
    )
    assert cleaned == ["TOTAL RM7.70", "Kedai Ali"]
    assert text == "TOTAL RM7.70\nKedai Ali"
    assert len(corrections) == 1


def test_coerce_cleanup_fields_never_raises_on_malformed_candidate() -> None:
    lines = [OcrLineResult(text="A", height_ratio=0.1, confidence=0.5)]
    # A deeply malformed candidate (nested dict where a string is expected)
    # must degrade to "no cleanup," never raise past this boundary — the
    # exact regression this function exists to prevent (see main.py's
    # OCR-succeeds-even-if-LLM-fails contract).
    cleaned, text, corrections = _coerce_cleanup_fields(
        [{"unexpected": "shape"}], cleanup_lines=lines
    )
    assert cleaned == ["A"]
    assert text == "A"
    assert corrections == []


def test_build_cleanup_line_block_numbers_and_tags_confidence() -> None:
    lines = [
        OcrLineResult(text="TOTAL RM7.70", height_ratio=0.05, confidence=0.91),
        OcrLineResult(text="Kedai Ali", height_ratio=0.1, confidence=0.42),
    ]
    block = _build_cleanup_line_block(lines)
    assert block == (
        "[0] (confidence 0.91) TOTAL RM7.70\n[1] (confidence 0.42) Kedai Ali"
    )


def test_select_cleanup_lines_none_when_disabled_by_default(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("LLM_CLEANUP_ENABLED", raising=False)
    lines = [OcrLineResult(text="TOTAL RM7.70 Kedai Ali food", height_ratio=0.05)]
    assert _select_cleanup_lines(lines) is None


def test_select_cleanup_lines_none_when_no_lines(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("LLM_CLEANUP_ENABLED", "1")
    assert _select_cleanup_lines(None) is None
    assert _select_cleanup_lines([]) is None


def test_select_cleanup_lines_none_below_word_floor(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("LLM_CLEANUP_ENABLED", "1")
    monkeypatch.setenv("LLM_CLEANUP_MIN_WORDS", "4")
    lines = [OcrLineResult(text="hi there", height_ratio=0.05)]  # 2 words
    assert _select_cleanup_lines(lines) is None


def test_select_cleanup_lines_present_when_enabled_and_enough_text(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("LLM_CLEANUP_ENABLED", "1")
    monkeypatch.setenv("LLM_CLEANUP_MIN_WORDS", "4")
    lines = [OcrLineResult(text="TOTAL RM7.70 Kedai Ali food", height_ratio=0.05)]
    assert _select_cleanup_lines(lines) == lines


def test_select_cleanup_lines_none_when_over_prompt_budget(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("LLM_CLEANUP_ENABLED", "1")
    monkeypatch.setenv("LLM_CLEANUP_MIN_WORDS", "1")
    import ocr_api.receipt_understanding as ru

    monkeypatch.setattr(ru, "MAX_OCR_PROMPT_CHARS", 20)
    lines = [OcrLineResult(text="a fairly long receipt line of text", height_ratio=0.1)]
    assert _select_cleanup_lines(lines) is None


# ---------------------------------------------------------------------------
# parse_receipt_understanding: cleaned_lines/cleaned_ocr_text/corrections
# ---------------------------------------------------------------------------


def test_parse_receipt_understanding_applies_cleanup_guard() -> None:
    payload = dict(MCD_JSON)
    payload["cleaned_lines"] = ["MCDONALD'S PAVILION KL", "TOTAL RM7.70"]
    cleanup_lines = [
        OcrLineResult(text="MCDONALD'S PAVILION KL", height_ratio=0.1),
        OcrLineResult(text="T0TAL RM7.70", height_ratio=0.05),
    ]
    u = parse_receipt_understanding(json.dumps(payload), cleanup_lines=cleanup_lines)
    assert u is not None
    # Line 0 unchanged; line 1's single-char fix is well under the guard's
    # default edit-distance threshold.
    assert u.cleaned_lines == ["MCDONALD'S PAVILION KL", "TOTAL RM7.70"]
    assert u.cleaned_ocr_text == "MCDONALD'S PAVILION KL\nTOTAL RM7.70"
    assert len(u.corrections) == 1
    assert u.corrections[0].line_index == 1


def test_parse_receipt_understanding_no_cleanup_fields_when_not_attempted() -> None:
    u = parse_receipt_understanding(json.dumps(MCD_JSON))
    assert u is not None
    assert u.cleaned_lines is None
    assert u.cleaned_ocr_text is None
    assert u.corrections == []


def test_parse_receipt_understanding_ignores_malformed_cleaned_lines() -> None:
    payload = dict(MCD_JSON)
    payload["cleaned_lines"] = "not a list"
    cleanup_lines = [OcrLineResult(text="MCDONALD'S PAVILION KL", height_ratio=0.1)]
    u = parse_receipt_understanding(json.dumps(payload), cleanup_lines=cleanup_lines)
    assert u is not None
    assert u.cleaned_lines is None
    assert u.corrections == []
    # The rest of the response is unaffected by the malformed cleanup field.
    assert u.merchant_name == "McDonald's Pavilion KL"


# ---------------------------------------------------------------------------
# call_receipt_understanding (httpx.MockTransport — no real network)
# ---------------------------------------------------------------------------


@pytest.fixture(autouse=True)
def _set_llm_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("LLM_PROVIDER", "vllm")
    monkeypatch.setenv("VLLM_BASE_URL", "http://gateway.local:31180")
    monkeypatch.setenv("VLLM_MODEL_NAME", "test-model")
    monkeypatch.setenv("VLLM_API_KEY", "sk-test")
    monkeypatch.delenv("VLLM_REASONING_EFFORT", raising=False)
    monkeypatch.delenv("DEEPSEEK_BASE_URL", raising=False)
    monkeypatch.delenv("DEEPSEEK_API_KEY", raising=False)
    monkeypatch.delenv("DEEPSEEK_MODEL_NAME", raising=False)
    monkeypatch.delenv("LLM_CLEANUP_ENABLED", raising=False)


async def test_call_returns_validated_understanding() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url == "http://gateway.local:31180/v1/chat/completions"
        return httpx.Response(200, content=_chat_content(json.dumps(MCD_JSON)))

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        result = await call_receipt_understanding("MCDONALD'S...", http_client=client)
    assert result.merchant_name == "McDonald's Pavilion KL"


async def test_call_with_lines_but_cleanup_disabled_sends_flattened_text() -> None:
    # LLM_CLEANUP_ENABLED unset (default off, via the autouse fixture above) —
    # passing `lines` must not change today's request shape or response.
    lines = [
        OcrLineResult(text="MCDONALD'S PAVILION KL", height_ratio=0.1),
        OcrLineResult(text="T0TAL RM5O.OO fast food burger", height_ratio=0.05),
    ]

    def handler(request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        user_content = body["messages"][1]["content"]
        assert "MCDONALD'S PAVILION KL" in user_content
        assert "[0]" not in user_content  # no per-line cleanup framing
        return httpx.Response(200, content=_chat_content(json.dumps(MCD_JSON)))

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        result = await call_receipt_understanding(
            "MCDONALD'S PAVILION KL\nT0TAL RM5O.OO fast food burger",
            http_client=client,
            lines=lines,
        )
    assert result.merchant_name == "McDonald's Pavilion KL"
    assert result.cleaned_lines is None


async def test_call_with_cleanup_enabled_sends_per_line_confidence_prompt(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("LLM_CLEANUP_ENABLED", "1")
    lines = [
        OcrLineResult(text="MCDONALD'S PAVILION KL", height_ratio=0.1, confidence=0.9),
        OcrLineResult(
            text="T0TAL RM5O.OO fast food burger", height_ratio=0.05, confidence=0.4
        ),
    ]
    cleanup_payload = dict(MCD_JSON)
    cleanup_payload["cleaned_lines"] = [
        "MCDONALD'S PAVILION KL",
        "TOTAL RM50.00 fast food burger",
    ]

    def handler(request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        system_content = body["messages"][0]["content"]
        user_content = body["messages"][1]["content"]
        # Prompt-input reshape actually happened — not just prompt text.
        assert "[0] (confidence 0.90) MCDONALD'S PAVILION KL" in user_content
        assert "[1] (confidence 0.40) T0TAL RM5O.OO fast food burger" in user_content
        assert "cleaned_lines" in system_content
        return httpx.Response(200, content=_chat_content(json.dumps(cleanup_payload)))

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        result = await call_receipt_understanding(
            "MCDONALD'S PAVILION KL\nT0TAL RM5O.OO fast food burger",
            http_client=client,
            lines=lines,
        )
    assert result.cleaned_lines == [
        "MCDONALD'S PAVILION KL",
        "TOTAL RM50.00 fast food burger",
    ]
    assert result.cleaned_ocr_text == (
        "MCDONALD'S PAVILION KL\nTOTAL RM50.00 fast food burger"
    )
    assert len(result.corrections) == 1
    assert result.corrections[0].line_index == 1


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


async def test_call_uses_deepseek_when_provider_set(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("LLM_PROVIDER", "deepseek")
    monkeypatch.setenv("DEEPSEEK_API_KEY", "sk-deepseek")
    monkeypatch.setenv("DEEPSEEK_MODEL_NAME", "deepseek-chat")
    # Leave DEEPSEEK_BASE_URL unset → default api.deepseek.com/v1

    def handler(request: httpx.Request) -> httpx.Response:
        assert str(request.url) == "https://api.deepseek.com/v1/chat/completions"
        assert request.headers["Authorization"] == "Bearer sk-deepseek"
        body = json.loads(request.content)
        assert body["model"] == "deepseek-chat"
        assert "reasoning_effort" not in body
        return httpx.Response(200, content=_chat_content(json.dumps(MCD_JSON)))

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        result = await call_receipt_understanding("MCDONALD'S...", http_client=client)
    assert result.merchant_name == "McDonald's Pavilion KL"


def test_resolve_llm_config_unknown_provider(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("LLM_PROVIDER", "openai")
    with pytest.raises(ReceiptUnderstandingError) as exc_info:
        resolve_llm_config()
    assert exc_info.value.code == "server_misconfigured"
    assert "unknown LLM_PROVIDER" in exc_info.value.detail


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
