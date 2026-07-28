"""LLM curator for spending-insight candidates.

Takes a small structured candidate pool (never raw transactions/OCR) and
returns up to 3 friendly, non-judgmental rewrite sentences. Validates every
field against a closed type vocabulary — same "hint, not authority" stance
as parse_receipt_understanding().
"""

from __future__ import annotations

import json
import logging
import re
from typing import Any

import httpx
from pydantic import BaseModel, Field

from ocr_api.receipt_understanding import (
    LLM_TIMEOUT_SECONDS,
    ReceiptUnderstandingError,
    _chat_completions_url,
    resolve_llm_config,
)

logger = logging.getLogger("ocr_api.insight_curator")

ALLOWED_TYPES = frozenset(
    {
        "spending_spike",
        "category_shift",
        "habit",
        "streak",
        "forecast",
    }
)
MAX_INSIGHTS = 3
LLM_MAX_TOKENS = 600

_SYSTEM_PROMPT = """\
You are a friendly spending-insights curator for a Malaysian receipt tracker.
You receive a JSON list of insight CANDIDATES. Each has type, fact_key, facts,
severity, and an optional template_hint.

Your job:
1. Deduplicate candidates that say essentially the same thing.
2. Rank by usefulness/novelty (prefer higher severity when tied).
3. Select at most 3.
4. Rewrite each selected candidate into ONE short, encouraging, non-judgmental
   sentence in English. Never invent numbers, categories, places, or facts
   that are not present in that candidate's facts/template_hint. Never compare
   the user to other people. Never frame observations as warnings or budgets.

Respond with ONLY a JSON object:
{"insights":[{"type":"...","fact_key":"...","body":"..."}, ...]}

type must be one of: spending_spike, category_shift, habit, streak, forecast.
fact_key must exactly match a candidate's fact_key.
"""


class InsightCandidateIn(BaseModel):
    type: str
    fact_key: str
    facts: dict[str, Any] = Field(default_factory=dict)
    severity: float = 0.0
    template_hint: str | None = None


class CurateInsightsRequest(BaseModel):
    candidates: list[InsightCandidateIn]


class CuratedInsightOut(BaseModel):
    type: str
    fact_key: str
    body: str


class CurateInsightsResponse(BaseModel):
    insights: list[CuratedInsightOut]


def _extract_json_object(raw: str) -> str | None:
    s = re.sub(r"<think>[\s\S]*?</think>", "", raw, flags=re.IGNORECASE)
    fence = re.search(r"```(?:json)?\s*([\s\S]*?)```", s, flags=re.IGNORECASE)
    if fence:
        s = fence.group(1)
    start = s.find("{")
    end = s.rfind("}")
    if start == -1 or end == -1 or end <= start:
        return None
    return s[start : end + 1]


def parse_curated_insights(
    raw: str, candidates: list[InsightCandidateIn]
) -> CurateInsightsResponse | None:
    """Validate LLM output against the closed schema + candidate whitelist."""
    json_text = _extract_json_object(raw)
    if json_text is None:
        return None
    try:
        obj = json.loads(json_text)
    except json.JSONDecodeError:
        return None
    if not isinstance(obj, dict):
        return None
    items = obj.get("insights")
    if not isinstance(items, list):
        return None

    by_fact = {c.fact_key: c for c in candidates}
    out: list[CuratedInsightOut] = []
    seen: set[str] = set()
    for entry in items:
        if not isinstance(entry, dict):
            continue
        typ = entry.get("type")
        fact_key = entry.get("fact_key") or entry.get("factKey")
        body = entry.get("body")
        if not isinstance(typ, str) or typ not in ALLOWED_TYPES:
            continue
        if not isinstance(fact_key, str) or not fact_key:
            continue
        if not isinstance(body, str) or not body.strip():
            continue
        if fact_key in seen:
            continue
        source = by_fact.get(fact_key)
        if source is None or source.type != typ:
            continue
        seen.add(fact_key)
        out.append(CuratedInsightOut(type=typ, fact_key=fact_key, body=body.strip()))
        if len(out) >= MAX_INSIGHTS:
            break
    if not out:
        return None
    return CurateInsightsResponse(insights=out)


def template_fallback(
    candidates: list[InsightCandidateIn],
) -> CurateInsightsResponse:
    """Non-LLM soft-launch path: use template_hint or a minimal fact sentence."""
    ranked = sorted(candidates, key=lambda c: c.severity, reverse=True)
    out: list[CuratedInsightOut] = []
    for c in ranked[:MAX_INSIGHTS]:
        body = (c.template_hint or "").strip()
        if not body:
            body = f"Something notable about your {c.type.replace('_', ' ')}"
        out.append(CuratedInsightOut(type=c.type, fact_key=c.fact_key, body=body))
    return CurateInsightsResponse(insights=out)


async def call_insight_curator(
    candidates: list[InsightCandidateIn],
    *,
    http_client: httpx.AsyncClient,
    use_llm: bool = True,
) -> CurateInsightsResponse:
    sanitized = [c for c in candidates if c.type in ALLOWED_TYPES and c.fact_key][:20]
    if not sanitized:
        return CurateInsightsResponse(insights=[])
    if not use_llm:
        return template_fallback(sanitized)

    cfg = resolve_llm_config()
    url = _chat_completions_url(cfg.base_url)
    headers = {"Content-Type": "application/json"}
    if cfg.api_key:
        headers["Authorization"] = f"Bearer {cfg.api_key}"

    payload_candidates = [
        {
            "type": c.type,
            "fact_key": c.fact_key,
            "facts": c.facts,
            "severity": c.severity,
            **({"template_hint": c.template_hint} if c.template_hint else {}),
        }
        for c in sanitized
    ]
    messages = [
        {"role": "system", "content": _SYSTEM_PROMPT},
        {
            "role": "user",
            "content": json.dumps({"candidates": payload_candidates}),
        },
    ]

    def _body(with_response_format: bool) -> dict[str, object]:
        body: dict[str, object] = {
            "model": cfg.model_name,
            "messages": messages,
            "temperature": 0.3,
            "max_tokens": LLM_MAX_TOKENS,
        }
        if with_response_format:
            body["response_format"] = {"type": "json_object"}
        if cfg.reasoning_effort:
            body["reasoning_effort"] = cfg.reasoning_effort
        return body

    try:
        resp = await http_client.post(
            url, headers=headers, json=_body(True), timeout=LLM_TIMEOUT_SECONDS
        )
        if resp.status_code == 400:
            resp = await http_client.post(
                url,
                headers=headers,
                json=_body(False),
                timeout=LLM_TIMEOUT_SECONDS,
            )
    except httpx.TimeoutException as exc:
        raise ReceiptUnderstandingError("llm_timeout", str(exc)) from exc
    except httpx.HTTPError as exc:
        raise ReceiptUnderstandingError("llm_fetch_failed", str(exc)) from exc

    if resp.status_code != 200:
        raise ReceiptUnderstandingError(
            f"llm_http_{resp.status_code}",
            "non-2xx from LLM gateway",
            resp.text[:500],
        )

    try:
        content = resp.json()["choices"][0]["message"]["content"]
    except (ValueError, KeyError, IndexError, TypeError) as exc:
        raise ReceiptUnderstandingError("llm_invalid_response_json", str(exc)) from exc

    parsed = parse_curated_insights(content, sanitized)
    if parsed is None:
        logger.warning("curator LLM response unusable — falling back to templates")
        return template_fallback(sanitized)
    return parsed
