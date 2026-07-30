"""Tests for the LangGraph insight curation workflow."""

from __future__ import annotations

import json

import httpx
import pytest

from ocr_api.insight_curator import InsightCandidateIn
from ocr_api.insights.graph import (
    build_insight_graph,
    run_insight_graph,
    specialist_node,
)
from ocr_api.insights.specialist_agents import (
    deterministic_drafts,
    validate_specialist_drafts,
)


def _c(typ: str, fact_key: str, severity: float = 0.5) -> InsightCandidateIn:
    return InsightCandidateIn(
        type=typ,
        fact_key=fact_key,
        facts={"n": 1},
        severity=severity,
        template_hint=f"hint {fact_key}",
    )


@pytest.mark.asyncio
async def test_phase2_graph_empty_pool_skips_llm(monkeypatch: pytest.MonkeyPatch):
    called = {"n": 0}

    async def _boom(*args, **kwargs):
        called["n"] += 1
        raise AssertionError("LLM must not be called for empty pool")

    monkeypatch.setattr("ocr_api.insights.graph.run_critic", _boom)
    async with httpx.AsyncClient() as client:
        result = await run_insight_graph(
            [], http_client=client, use_llm=True, use_specialists=False
        )
    assert result.insights == []
    assert called["n"] == 0


@pytest.mark.asyncio
async def test_prefilter_weak_pool_skips_llm(monkeypatch: pytest.MonkeyPatch):
    """Below-floor candidates must not reach the Critic."""
    called = {"n": 0}

    async def _boom(*args, **kwargs):
        called["n"] += 1
        raise AssertionError("LLM must not be called for pre-filtered pool")

    monkeypatch.setattr("ocr_api.insights.graph.run_critic", _boom)
    cands = [_c("streak", "streak:1", severity=0.2)]
    async with httpx.AsyncClient() as client:
        result = await run_insight_graph(
            cands, http_client=client, use_llm=True, use_specialists=False
        )
    assert result.insights == []
    assert called["n"] == 0


@pytest.mark.asyncio
async def test_phase2_graph_template_path_no_llm(monkeypatch: pytest.MonkeyPatch):
    cands = [_c("streak", "streak:3"), _c("habit", "habit:tealive")]
    async with httpx.AsyncClient() as client:
        result = await run_insight_graph(
            cands, http_client=client, use_llm=False, use_specialists=False
        )
    assert len(result.insights) == 2
    assert {i.fact_key for i in result.insights} == {
        "streak:3",
        "habit:tealive",
    }


@pytest.mark.asyncio
async def test_parallel_fanout_state_merge(monkeypatch: pytest.MonkeyPatch):
    """Three specialists must all contribute — catches reducer clobber bugs."""
    cands = [
        _c("streak", "streak:1"),
        _c("habit", "habit:1"),
        _c("forecast", "forecast:1"),
    ]

    async def fake_specialist(agent, signals, *, http_client, use_llm=True):
        return list(signals)

    monkeypatch.setattr("ocr_api.insights.graph.run_specialist", fake_specialist)

    async with httpx.AsyncClient() as client:
        result = await run_insight_graph(
            cands,
            http_client=client,
            use_llm=False,
            use_specialists=True,
        )
    keys = {i.fact_key for i in result.insights}
    assert keys == {"streak:1", "habit:1", "forecast:1"}


@pytest.mark.asyncio
async def test_partial_specialist_failure_still_completes(
    monkeypatch: pytest.MonkeyPatch,
):
    async def flaky(agent, signals, *, http_client, use_llm=True):
        if agent == "motivation_agent":
            raise RuntimeError("boom")
        return list(signals)

    monkeypatch.setattr("ocr_api.insights.graph.run_specialist", flaky)

    cands = [
        _c("streak", "streak:1"),
        _c("habit", "habit:1"),
    ]
    async with httpx.AsyncClient() as client:
        result = await run_insight_graph(
            cands,
            http_client=client,
            use_llm=False,
            use_specialists=True,
        )
    # Streak specialist crashed → only habit survives.
    assert [i.fact_key for i in result.insights] == ["habit:1"]


@pytest.mark.asyncio
async def test_all_specialists_fail_yields_zero_insights(
    monkeypatch: pytest.MonkeyPatch,
):
    async def always_fail(agent, signals, *, http_client, use_llm=True):
        raise RuntimeError("down")

    monkeypatch.setattr("ocr_api.insights.graph.run_specialist", always_fail)

    cands = [_c("streak", "streak:1"), _c("habit", "habit:1")]
    async with httpx.AsyncClient() as client:
        result = await run_insight_graph(
            cands,
            http_client=client,
            use_llm=False,
            use_specialists=True,
        )
    assert result.insights == []


@pytest.mark.asyncio
async def test_specialist_node_returns_empty_on_crash():
    async def boom(*args, **kwargs):
        raise RuntimeError("x")

    # Direct node call with a config that will hit run_specialist via import —
    # patch at the module the node uses.
    import ocr_api.insights.graph as graph_mod

    original = graph_mod.run_specialist
    graph_mod.run_specialist = boom  # type: ignore[assignment]
    try:
        out = await specialist_node(
            {
                "agent": "motivation_agent",
                "signals": [_c("streak", "s:1")],
                "use_llm": True,
            },
            {"configurable": {"http_client": httpx.AsyncClient()}},
        )
        assert out == {"candidate_insights": []}
    finally:
        graph_mod.run_specialist = original


def test_validate_specialist_drafts_rejects_fabricated_fact_key():
    signals = [_c("streak", "streak:real")]
    raw = json.dumps(
        {
            "drafts": [
                {
                    "type": "streak",
                    "fact_key": "made-up",
                    "body": "Nope",
                    "severity": 0.9,
                }
            ]
        }
    )
    assert validate_specialist_drafts(raw, signals, expected_type="streak") == []


def test_validate_specialist_drafts_accepts_traceable():
    signals = [_c("habit", "habit:tealive", severity=0.6)]
    raw = json.dumps(
        {
            "drafts": [
                {
                    "type": "habit",
                    "fact_key": "habit:tealive",
                    "body": "Tealive is a regular stop.",
                    "severity": 0.7,
                }
            ]
        }
    )
    drafts = validate_specialist_drafts(raw, signals, expected_type="habit")
    assert len(drafts) == 1
    assert drafts[0].template_hint == "Tealive is a regular stop."
    assert drafts[0].severity == 0.7


def test_deterministic_drafts_passthrough():
    signals = [_c("forecast", "forecast:1")]
    assert deterministic_drafts(signals) == signals


def test_graph_compiles():
    g = build_insight_graph()
    assert g is not None


@pytest.mark.asyncio
async def test_visualization_attached_after_critic_in_template_path():
    """The visualization node runs after Critic even on the non-LLM path."""
    cands = [
        InsightCandidateIn(
            type="habit",
            fact_key="habit:tealive",
            facts={"place_name": "Tealive", "visits": 5, "window_days": 7},
            severity=0.6,
            template_hint="You visited Tealive 5 times this week",
        ),
        _c("streak", "streak:3"),
    ]
    async with httpx.AsyncClient() as client:
        result = await run_insight_graph(
            cands, http_client=client, use_llm=False, use_specialists=False
        )
    by_key = {i.fact_key: i for i in result.insights}
    assert by_key["habit:tealive"].visualization is not None
    assert by_key["habit:tealive"].visualization["type"] == "habit_timeline"
    # streak has no rule — must degrade to None, never fabricate one.
    assert by_key["streak:3"].visualization is None
