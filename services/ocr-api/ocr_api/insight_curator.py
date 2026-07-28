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

CRITIC_SYSTEM_PROMPT = """\
You are the Insight Critic for Receipt Drop, a Malaysian receipt-first spend tracker.
You are a friendly spending companion — never a financial advisor, coach, or budget app.

You receive ONE JSON object with:
- "candidates": pre-filtered insight candidates. Each has:
  type, fact_key, facts, severity, and optional template_hint
  (detector or specialist draft text — NOT authoritative wording).
- "user_feedback" (optional):
  dismissed_fact_keys: string[]
  dismiss_counts: { [fact_key]: number }

ALLOWED types ONLY:
spending_spike, category_shift, habit, streak, forecast.

YOUR JOB (in order):
1) DISCARD any candidate whose fact_key is in dismissed_fact_keys, or whose
   facts you cannot support, or that invents content you would need to add.
2) DEDUPLICATE: same type + same category/merchant/place = one idea.
   Cross-type same entity = keep the higher-severity candidate only.
3) RANK by: severity (and any specialist confidence implied in hints),
   then novelty vs dismiss_counts (higher dismiss count = lower rank),
   then type diversity.
4) SELECT at most 3. Prefer fewer strong insights over many weak ones.
   Returning zero insights is allowed and preferred over weak filler.
5) WRITE user-facing copy:
   - Always REWRITE; do not paste template_hint or specialist drafts.
   - title: short label (≤6 words), no emoji required.
   - description: ONE short encouraging non-judgmental English sentence.
   - priority: number 0..1 reflecting your final rank strength.
   - Use ONLY numbers/names/categories that appear in that candidate's facts
     (or clearly in its template_hint). Never invent.
   - Never compare the user to other people.
   - Never warn, shame, or prescribe budgets/limits.
   - Vary openings: no two descriptions may start with the same three words.

MERGE RULE:
Do not create a new fact_key. If two candidates are the same idea, keep the
winner's fact_key and facts only.

OUTPUT:
Respond with ONLY a JSON object (no markdown, no commentary):
{
  "insights": [
    {
      "type": "habit",
      "fact_key": "must-match-a-candidate-fact_key",
      "title": "Coffee is becoming a habit",
      "description": "You visited Starbucks 5 times this week.",
      "priority": 0.82
    }
  ]
}

Constraints:
- insights length ≤ 3
- each type must match the source candidate with that fact_key
- each fact_key must exactly match an input candidate
- unique fact_keys in the array
- if nothing strong remains, return {"insights":[]}
"""

# Legacy alias for imports that reference _SYSTEM_PROMPT.
_SYSTEM_PROMPT = CRITIC_SYSTEM_PROMPT


class InsightCandidateIn(BaseModel):
    type: str
    fact_key: str
    facts: dict[str, Any] = Field(default_factory=dict)
    severity: float = 0.0
    template_hint: str | None = None


class CurateInsightsRequest(BaseModel):
    candidates: list[InsightCandidateIn]
    dismissed_fact_keys: list[str] | None = None
    # Per fact_key dismiss counts from the client (aggregated to type weights server-side).
    dismiss_counts: dict[str, int] | None = None


class CuratedInsightOut(BaseModel):
    type: str
    fact_key: str
    body: str
    priority: float = 0.0


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


def _allowed_numeric_tokens(source: InsightCandidateIn) -> set[str]:
    """Tokens the Critic may use in title/description for this candidate."""
    allowed: set[str] = set()
    for v in (source.facts or {}).values():
        if v is None:
            continue
        allowed.add(str(v))
    if source.template_hint:
        allowed.update(re.findall(r"\d+(?:\.\d+)?", source.template_hint))
    return allowed


def _body_invents_numbers(body: str, source: InsightCandidateIn) -> bool:
    """True if body contains numeric tokens not traceable to facts/hint."""
    nums_in_body = set(re.findall(r"\d+(?:\.\d+)?", body))
    if not nums_in_body:
        return False
    allowed = _allowed_numeric_tokens(source)
    return not nums_in_body.issubset(allowed)


def _compose_body(
    *,
    body: str | None,
    title: str | None,
    description: str | None,
) -> str | None:
    if body and body.strip():
        return body.strip()
    desc = (description or "").strip()
    tit = (title or "").strip()
    if tit and desc:
        return f"{tit}. {desc}"
    if desc:
        return desc
    if tit:
        return tit
    return None


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
    parsed: list[tuple[float, CuratedInsightOut]] = []
    seen: set[str] = set()
    for entry in items:
        if not isinstance(entry, dict):
            continue
        typ = entry.get("type")
        fact_key = entry.get("fact_key") or entry.get("factKey")
        title = entry.get("title")
        description = entry.get("description")
        legacy_body = entry.get("body")
        priority_raw = entry.get("priority")
        if not isinstance(typ, str) or typ not in ALLOWED_TYPES:
            continue
        if not isinstance(fact_key, str) or not fact_key:
            continue
        body = _compose_body(
            body=legacy_body if isinstance(legacy_body, str) else None,
            title=title if isinstance(title, str) else None,
            description=description if isinstance(description, str) else None,
        )
        if not body:
            continue
        if fact_key in seen:
            continue
        source = by_fact.get(fact_key)
        if source is None or source.type != typ:
            continue
        if len(body) > 200:
            continue
        if isinstance(title, str) and len(title.strip()) > 60:
            continue
        if _body_invents_numbers(body, source):
            continue
        priority = 0.0
        if isinstance(priority_raw, (int, float)):
            priority = max(0.0, min(1.0, float(priority_raw)))
        seen.add(fact_key)
        parsed.append(
            (
                priority,
                CuratedInsightOut(
                    type=typ, fact_key=fact_key, body=body, priority=priority
                ),
            )
        )

    if not parsed:
        return None

    parsed.sort(key=lambda x: x[0], reverse=True)
    out = [item for _, item in parsed[:MAX_INSIGHTS]]
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
        out.append(
            CuratedInsightOut(
                type=c.type,
                fact_key=c.fact_key,
                body=body,
                priority=c.severity,
            )
        )
    return CurateInsightsResponse(insights=out)


async def run_critic(
    eligible: list[InsightCandidateIn],
    *,
    http_client: httpx.AsyncClient,
    use_llm: bool = True,
    system_prompt: str | None = None,
    dismissed_fact_keys: list[str] | None = None,
    dismiss_counts: dict[str, int] | None = None,
) -> CurateInsightsResponse:
    """Dedupe/rank/rewrite pass over an already-routed candidate (or draft) pool.

    This is the Critic node body. Does not re-run the insight_router — callers
    (call_insight_curator, the LangGraph critic node) must supply the eligible
    slice. On malformed LLM output, degrades to template_fallback.
    """
    if not eligible:
        return CurateInsightsResponse(insights=[])
    if not use_llm:
        return template_fallback(eligible)

    cfg = resolve_llm_config()
    url = _chat_completions_url(cfg.base_url)
    headers = {"Content-Type": "application/json"}
    if cfg.api_key:
        headers["Authorization"] = f"Bearer {cfg.api_key}"

    prompt = system_prompt or CRITIC_SYSTEM_PROMPT
    payload_candidates = [
        {
            "type": c.type,
            "fact_key": c.fact_key,
            "facts": c.facts,
            "severity": c.severity,
            **({"template_hint": c.template_hint} if c.template_hint else {}),
        }
        for c in eligible
    ]
    user_payload: dict[str, object] = {"candidates": payload_candidates}
    if dismissed_fact_keys or dismiss_counts:
        user_payload["user_feedback"] = {
            "dismissed_fact_keys": dismissed_fact_keys or [],
            "dismiss_counts": dismiss_counts or {},
        }
    messages = [
        {"role": "system", "content": prompt},
        {
            "role": "user",
            "content": json.dumps(user_payload),
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

    parsed = parse_curated_insights(content, eligible)
    if parsed is None:
        logger.warning("curator LLM response unusable — falling back to templates")
        return template_fallback(eligible)
    return parsed


async def call_insight_curator(
    candidates: list[InsightCandidateIn],
    *,
    http_client: httpx.AsyncClient,
    use_llm: bool = True,
    engagement_weights: dict[str, float] | None = None,
) -> CurateInsightsResponse:
    """Legacy/direct path: sanitize → route → critic. Prefer run_insight_graph."""
    sanitized = [c for c in candidates if c.type in ALLOWED_TYPES and c.fact_key][:20]
    if not sanitized:
        return CurateInsightsResponse(insights=[])

    from ocr_api.insights.insight_router import route_candidates

    decision = route_candidates(sanitized, engagement_weights=engagement_weights)
    if decision.is_empty:
        return CurateInsightsResponse(insights=[])
    eligible = [r.candidate for r in decision.eligible]
    return await run_critic(eligible, http_client=http_client, use_llm=use_llm)
