"""Narrow specialist agents for insight curation (Phase 3).

Each agent receives only the signal slice the insight_router assigned to it,
emits zero or more structured drafts (still fact_key-traceable), and must
never invent a fact_key/type not present in its input. Gated by
INSIGHTS_SPECIALIST_AGENTS_ENABLED at the graph layer.
"""

from __future__ import annotations

import json
import logging
from typing import Any

import httpx

from ocr_api.insight_curator import (
    ALLOWED_TYPES,
    LLM_MAX_TOKENS,
    InsightCandidateIn,
    _extract_json_object,
)
from ocr_api.receipt_understanding import (
    LLM_TIMEOUT_SECONDS,
    ReceiptUnderstandingError,
    _chat_completions_url,
    resolve_llm_config,
)

logger = logging.getLogger("ocr_api.insights.specialist_agents")

# Per-agent system prompts — narrow domain focus; final voice stays in Critic.
_AGENT_PROMPTS: dict[str, str] = {
    "spending_anomaly_agent": """\
You are a spending-anomaly specialist for a Malaysian receipt tracker.
You receive ONLY spending_spike candidates. Produce structured drafts that
highlight the spike clearly. Do not invent numbers or facts. Respond with
ONLY JSON:
{"drafts":[{"type":"spending_spike","fact_key":"...","body":"...","severity":0.0}, ...]}
fact_key must match an input candidate. body is a short draft sentence for the Critic.
""",
    "category_behavior_agent": """\
You are a category-behavior specialist for a Malaysian receipt tracker.
You receive ONLY category_shift candidates. Produce structured drafts about
category spend changes. Do not invent numbers or facts. Respond with ONLY JSON:
{"drafts":[{"type":"category_shift","fact_key":"...","body":"...","severity":0.0}, ...]}
fact_key must match an input candidate.
""",
    "merchant_habit_agent": """\
You are a merchant-habit specialist for a Malaysian receipt tracker.
You receive ONLY habit candidates. Produce structured drafts about repeated
visits. Do not invent places or counts. Respond with ONLY JSON:
{"drafts":[{"type":"habit","fact_key":"...","body":"...","severity":0.0}, ...]}
fact_key must match an input candidate.
""",
    "motivation_agent": """\
You are a motivation/streak specialist for a Malaysian receipt tracker.
You receive ONLY streak candidates. Produce encouraging, non-judgmental drafts.
Do not invent streak lengths. Respond with ONLY JSON:
{"drafts":[{"type":"streak","fact_key":"...","body":"...","severity":0.0}, ...]}
fact_key must match an input candidate.
""",
    "forecast_agent": """\
You are a spend-forecast specialist for a Malaysian receipt tracker.
You receive ONLY forecast candidates. Produce observational (not warning)
drafts about pace vs prior month. Do not invent totals. Respond with ONLY JSON:
{"drafts":[{"type":"forecast","fact_key":"...","body":"...","severity":0.0}, ...]}
fact_key must match an input candidate.
""",
}

AGENT_NAMES = frozenset(_AGENT_PROMPTS)


def validate_specialist_drafts(
    raw: str,
    signals: list[InsightCandidateIn],
    *,
    expected_type: str | None = None,
) -> list[InsightCandidateIn]:
    """Reject fabricated fact_keys/types — first no-fabrication boundary."""
    json_text = _extract_json_object(raw)
    if json_text is None:
        return []
    try:
        obj = json.loads(json_text)
    except json.JSONDecodeError:
        return []
    if not isinstance(obj, dict):
        return []
    items = obj.get("drafts")
    if not isinstance(items, list):
        return []

    by_fact = {c.fact_key: c for c in signals}
    out: list[InsightCandidateIn] = []
    seen: set[str] = set()
    for entry in items:
        if not isinstance(entry, dict):
            continue
        typ = entry.get("type")
        fact_key = entry.get("fact_key") or entry.get("factKey")
        body = entry.get("body")
        if not isinstance(typ, str) or typ not in ALLOWED_TYPES:
            continue
        if expected_type is not None and typ != expected_type:
            continue
        if not isinstance(fact_key, str) or not fact_key or fact_key in seen:
            continue
        source = by_fact.get(fact_key)
        if source is None or source.type != typ:
            continue
        if not isinstance(body, str) or not body.strip():
            # Keep the source as a draft using its template_hint.
            body = (source.template_hint or "").strip() or None
            if not body:
                continue
        severity = entry.get("severity")
        if not isinstance(severity, (int, float)):
            severity = source.severity
        seen.add(fact_key)
        out.append(
            InsightCandidateIn(
                type=typ,
                fact_key=fact_key,
                facts=source.facts,
                severity=float(severity),
                template_hint=body.strip(),
            )
        )
    return out


def deterministic_drafts(
    signals: list[InsightCandidateIn],
) -> list[InsightCandidateIn]:
    """Non-LLM specialist path: pass signals through as drafts unchanged."""
    return list(signals)


async def run_specialist(
    agent: str,
    signals: list[InsightCandidateIn],
    *,
    http_client: httpx.AsyncClient,
    use_llm: bool = True,
) -> list[InsightCandidateIn]:
    """Run one specialist; on any failure return deterministic drafts (or []).

    Partial failure must not kill the cycle — the graph Critic proceeds with
    whatever drafts arrive. An empty return simply omits this agent's voice.
    """
    if not signals or agent not in _AGENT_PROMPTS:
        return []
    if not use_llm:
        return deterministic_drafts(signals)

    expected_type = next(
        (
            t
            for t, a in {
                "spending_spike": "spending_anomaly_agent",
                "category_shift": "category_behavior_agent",
                "habit": "merchant_habit_agent",
                "streak": "motivation_agent",
                "forecast": "forecast_agent",
            }.items()
            if a == agent
        ),
        None,
    )

    try:
        raw = await _call_specialist_llm(agent, signals, http_client=http_client)
    except Exception:
        logger.exception(
            "specialist %s failed — omitting its drafts for this cycle", agent
        )
        return []

    drafts = validate_specialist_drafts(raw, signals, expected_type=expected_type)
    if not drafts:
        logger.warning(
            "specialist %s returned unusable drafts — falling back to templates",
            agent,
        )
        return deterministic_drafts(signals)
    return drafts


async def _call_specialist_llm(
    agent: str,
    signals: list[InsightCandidateIn],
    *,
    http_client: httpx.AsyncClient,
) -> str:
    cfg = resolve_llm_config()
    url = _chat_completions_url(cfg.base_url)
    headers = {"Content-Type": "application/json"}
    if cfg.api_key:
        headers["Authorization"] = f"Bearer {cfg.api_key}"

    payload = [
        {
            "type": c.type,
            "fact_key": c.fact_key,
            "facts": c.facts,
            "severity": c.severity,
            **({"template_hint": c.template_hint} if c.template_hint else {}),
        }
        for c in signals
    ]
    messages = [
        {"role": "system", "content": _AGENT_PROMPTS[agent]},
        {"role": "user", "content": json.dumps({"candidates": payload})},
    ]

    def _body(with_response_format: bool) -> dict[str, Any]:
        body: dict[str, Any] = {
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
        return resp.json()["choices"][0]["message"]["content"]
    except (ValueError, KeyError, IndexError, TypeError) as exc:
        raise ReceiptUnderstandingError("llm_invalid_response_json", str(exc)) from exc
