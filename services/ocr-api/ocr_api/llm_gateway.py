"""Generic LLM-gateway client infrastructure shared by every LLM-touching
pipeline in this service (receipt understanding, payment-notification
understanding, ...). Extracted from ocr_api/receipt_understanding.py so a
second, independent pipeline doesn't have to duplicate provider config
resolution, the chat-completions URL builder, JSON-from-a-chatty-model
extraction, or the retry/timeout/non-2xx HTTP-call handling.

What stays OUT of this module deliberately: prompts, response schemas,
domain-specific parsing/validation, and any receipt- or payment-specific
business logic. Those live in each pipeline's own module
(receipt_understanding.py, payment_notification_understanding.py).
"""

from __future__ import annotations

import logging
import os
import re
import time
from dataclasses import dataclass

import httpx

logger = logging.getLogger("ocr_api.llm_gateway")

# Flip via root `.env` `LLM_PROVIDER=vllm|deepseek`. Keep both provider
# blocks filled in so switching is a one-line change + ocr-api restart.
_DEFAULT_DEEPSEEK_BASE_URL = "https://api.deepseek.com/v1"


class LlmGatewayError(Exception):
    """Raised on any LLM-gateway-call failure — timeout, non-2xx, or an
    unexpected response shape. Callers decide whether/how to fall back;
    this class itself carries no fallback behavior."""

    def __init__(self, code: str, detail: str, raw: str | None = None) -> None:
        super().__init__(detail)
        self.code = code
        self.detail = detail
        self.raw = raw


@dataclass(frozen=True)
class LlmEndpointConfig:
    provider: str
    base_url: str
    model_name: str
    api_key: str | None
    reasoning_effort: str | None


def resolve_llm_config() -> LlmEndpointConfig:
    """Pick active LLM endpoint from `LLM_PROVIDER` + the matching env block.

    Raises [LlmGatewayError] with code `server_misconfigured` when the
    active provider's required vars are missing, or the provider name is
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
        raise LlmGatewayError(
            "server_misconfigured",
            f"unknown LLM_PROVIDER={provider!r} (expected vllm or deepseek)",
        )

    if not base_url or not model_name:
        raise LlmGatewayError(
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


def chat_completions_url(base_url: str) -> str:
    base = base_url.rstrip("/")
    api_base = base if base.endswith("/v1") else f"{base}/v1"
    return f"{api_base}/chat/completions"


def extract_json_object(raw: str) -> str | None:
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


def clamp01(v: object) -> float:
    try:
        n = float(v)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return 0.0
    if n != n:  # NaN
        return 0.0
    return max(0.0, min(1.0, n))


def as_str_or_none(v: object) -> str | None:
    if not isinstance(v, str):
        return None
    t = v.strip()
    return t or None


def as_positive_float_or_none(v: object) -> float | None:
    if v is None or isinstance(v, bool):
        return None
    try:
        n = float(v)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return None
    if n != n or n < 0:  # NaN or negative
        return None
    return n


async def call_chat_completion(
    messages: list[dict[str, str]],
    *,
    cfg: LlmEndpointConfig,
    http_client: httpx.AsyncClient,
    max_tokens: int,
    timeout_seconds: float,
    use_response_format: bool = True,
) -> str:
    """Calls the configured OpenAI-compatible chat-completions endpoint and
    returns the raw message content string, or raises [LlmGatewayError].

    One narrow retry without `response_format` on HTTP 400 (some LiteLLM/
    vLLM backends reject it outright) — every other failure propagates
    immediately. Domain-specific parsing/validation of the returned content
    is the caller's responsibility, not this function's.
    """
    url = chat_completions_url(cfg.base_url)
    headers = {"Content-Type": "application/json"}
    if cfg.api_key:
        headers["Authorization"] = f"Bearer {cfg.api_key}"

    def _body(with_response_format: bool) -> dict[str, object]:
        body: dict[str, object] = {
            "model": cfg.model_name,
            "messages": messages,
            "temperature": 0,
            "max_tokens": max_tokens,
        }
        if with_response_format:
            body["response_format"] = {"type": "json_object"}
        if cfg.reasoning_effort:
            body["reasoning_effort"] = cfg.reasoning_effort
        return body

    start = time.perf_counter()
    try:
        resp = await http_client.post(
            url,
            headers=headers,
            json=_body(use_response_format),
            timeout=timeout_seconds,
        )
        if resp.status_code == 400 and use_response_format:
            resp = await http_client.post(
                url,
                headers=headers,
                json=_body(False),
                timeout=timeout_seconds,
            )
    except httpx.TimeoutException as exc:
        elapsed = time.perf_counter() - start
        logger.error("LLM gateway timed out after %.2fs", elapsed)
        raise LlmGatewayError("llm_timeout", str(exc)) from exc
    except httpx.HTTPError as exc:
        elapsed = time.perf_counter() - start
        logger.error("LLM gateway request failed after %.2fs: %s", elapsed, exc)
        raise LlmGatewayError("llm_fetch_failed", str(exc)) from exc

    elapsed = time.perf_counter() - start

    if resp.status_code != 200:
        body_text = resp.text[:500]
        logger.error(
            "LLM gateway returned HTTP %d after %.2fs: %s",
            resp.status_code,
            elapsed,
            body_text,
        )
        raise LlmGatewayError(
            f"llm_http_{resp.status_code}", "non-2xx from LLM gateway", body_text
        )

    try:
        payload = resp.json()
        content = payload["choices"][0]["message"]["content"]
    except (ValueError, KeyError, IndexError, TypeError) as exc:
        logger.error("LLM gateway returned an unexpected response shape: %s", exc)
        raise LlmGatewayError("llm_invalid_response_json", str(exc)) from exc

    logger.info(
        "LLM gateway call ok in %.2fs (provider=%s model=%s)",
        elapsed,
        cfg.provider,
        payload.get("model", cfg.model_name),
    )
    return content
