import json

import httpx
import pytest

from ocr_api.llm_gateway import (
    LlmGatewayError,
    as_positive_float_or_none,
    as_str_or_none,
    call_chat_completion,
    chat_completions_url,
    clamp01,
    extract_json_object,
    resolve_llm_config,
)


def _chat_content(text: str) -> str:
    return json.dumps(
        {"model": "test-model", "choices": [{"message": {"content": text}}]}
    )


# ---------------------------------------------------------------------------
# resolve_llm_config
# ---------------------------------------------------------------------------


def test_resolve_llm_config_vllm_default(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("LLM_PROVIDER", raising=False)
    monkeypatch.setenv("VLLM_BASE_URL", "https://gateway.example.com")
    monkeypatch.setenv("VLLM_MODEL_NAME", "qwen2.5-vl")
    cfg = resolve_llm_config()
    assert cfg.provider == "vllm"
    assert cfg.base_url == "https://gateway.example.com"
    assert cfg.model_name == "qwen2.5-vl"


def test_resolve_llm_config_deepseek(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("LLM_PROVIDER", "deepseek")
    monkeypatch.setenv("DEEPSEEK_MODEL_NAME", "deepseek-chat")
    monkeypatch.setenv("DEEPSEEK_API_KEY", "sk-test")
    cfg = resolve_llm_config()
    assert cfg.provider == "deepseek"
    assert cfg.base_url == "https://api.deepseek.com/v1"
    assert cfg.reasoning_effort is None


def test_resolve_llm_config_missing_vars_raises(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("VLLM_BASE_URL", raising=False)
    monkeypatch.delenv("VLLM_MODEL_NAME", raising=False)
    with pytest.raises(LlmGatewayError) as exc_info:
        resolve_llm_config()
    assert exc_info.value.code == "server_misconfigured"


def test_resolve_llm_config_unknown_provider(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("LLM_PROVIDER", "openai")
    with pytest.raises(LlmGatewayError) as exc_info:
        resolve_llm_config()
    assert exc_info.value.code == "server_misconfigured"
    assert "unknown LLM_PROVIDER" in exc_info.value.detail


# ---------------------------------------------------------------------------
# chat_completions_url
# ---------------------------------------------------------------------------


def test_chat_completions_url_appends_v1() -> None:
    assert (
        chat_completions_url("https://gateway.example.com")
        == "https://gateway.example.com/v1/chat/completions"
    )


def test_chat_completions_url_already_has_v1() -> None:
    assert (
        chat_completions_url("https://gateway.example.com/v1/")
        == "https://gateway.example.com/v1/chat/completions"
    )


# ---------------------------------------------------------------------------
# extract_json_object
# ---------------------------------------------------------------------------


def test_extract_json_object_plain() -> None:
    assert extract_json_object('{"a": 1}') == '{"a": 1}'


def test_extract_json_object_strips_think_block() -> None:
    raw = '<think>reasoning here</think>\n{"a": 1}'
    assert extract_json_object(raw) == '{"a": 1}'


def test_extract_json_object_strips_markdown_fence() -> None:
    raw = '```json\n{"a": 1}\n```'
    assert extract_json_object(raw) == '{"a": 1}'


def test_extract_json_object_no_braces_returns_none() -> None:
    assert extract_json_object("no json here") is None


# ---------------------------------------------------------------------------
# clamp01 / as_str_or_none / as_positive_float_or_none
# ---------------------------------------------------------------------------


def test_clamp01_bounds() -> None:
    assert clamp01(-5) == 0.0
    assert clamp01(5) == 1.0
    assert clamp01(0.42) == pytest.approx(0.42)
    assert clamp01("not a number") == 0.0


def test_as_str_or_none() -> None:
    assert as_str_or_none("  hi  ") == "hi"
    assert as_str_or_none("   ") is None
    assert as_str_or_none(123) is None
    assert as_str_or_none(None) is None


def test_as_positive_float_or_none() -> None:
    assert as_positive_float_or_none(18.5) == 18.5
    assert as_positive_float_or_none("18.5") == 18.5
    assert as_positive_float_or_none(-1) is None
    assert as_positive_float_or_none(None) is None
    assert as_positive_float_or_none(True) is None


# ---------------------------------------------------------------------------
# call_chat_completion
# ---------------------------------------------------------------------------


def _cfg(**overrides: object):
    from ocr_api.llm_gateway import LlmEndpointConfig

    defaults: dict[str, object] = {
        "provider": "vllm",
        "base_url": "https://gateway.example.com",
        "model_name": "test-model",
        "api_key": None,
        "reasoning_effort": None,
    }
    defaults.update(overrides)
    return LlmEndpointConfig(**defaults)  # type: ignore[arg-type]


async def test_call_chat_completion_success() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        assert body["model"] == "test-model"
        assert body["response_format"] == {"type": "json_object"}
        return httpx.Response(200, content=_chat_content('{"ok": true}'))

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        content = await call_chat_completion(
            [{"role": "user", "content": "hi"}],
            cfg=_cfg(),
            http_client=client,
            max_tokens=100,
            timeout_seconds=5,
        )
    assert content == '{"ok": true}'


async def test_call_chat_completion_retries_without_response_format_on_400() -> None:
    calls: list[dict[str, object]] = []

    def handler(request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        calls.append(body)
        if "response_format" in body:
            return httpx.Response(400, json={"error": "response_format not supported"})
        return httpx.Response(200, content=_chat_content('{"ok": true}'))

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        content = await call_chat_completion(
            [{"role": "user", "content": "hi"}],
            cfg=_cfg(),
            http_client=client,
            max_tokens=100,
            timeout_seconds=5,
        )
    assert content == '{"ok": true}'
    assert len(calls) == 2
    assert "response_format" not in calls[1]


async def test_call_chat_completion_timeout_raises() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.TimeoutException("timed out", request=request)

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        with pytest.raises(LlmGatewayError) as exc_info:
            await call_chat_completion(
                [{"role": "user", "content": "hi"}],
                cfg=_cfg(),
                http_client=client,
                max_tokens=100,
                timeout_seconds=5,
            )
    assert exc_info.value.code == "llm_timeout"


async def test_call_chat_completion_non_2xx_raises() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(500, text="upstream broke")

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        with pytest.raises(LlmGatewayError) as exc_info:
            await call_chat_completion(
                [{"role": "user", "content": "hi"}],
                cfg=_cfg(),
                http_client=client,
                max_tokens=100,
                timeout_seconds=5,
            )
    assert exc_info.value.code == "llm_http_500"


async def test_call_chat_completion_invalid_response_shape_raises() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"unexpected": "shape"})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        with pytest.raises(LlmGatewayError) as exc_info:
            await call_chat_completion(
                [{"role": "user", "content": "hi"}],
                cfg=_cfg(),
                http_client=client,
                max_tokens=100,
                timeout_seconds=5,
            )
    assert exc_info.value.code == "llm_invalid_response_json"
