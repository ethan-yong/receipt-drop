"""LangGraph insight-curation workflow.

Phase 2: SignalLoader → insight_router → Critic (one LLM call).
Phase 3: when use_specialists=True, router fans out via Send to specialist
nodes; Critic fans in over reducer-merged drafts.
Critic → visualization (rule-based Visualization Story Agent, not an LLM) →
END attaches a visual spec to each of the <=3 final insights.

http_client is passed through RunnableConfig.configurable so it never
lands in LLM prompt state. userId is intentionally absent from graph state.
"""

from __future__ import annotations

import logging
import operator
from typing import Annotated, Any, TypedDict

import httpx
from langchain_core.runnables import RunnableConfig
from langgraph.graph import END, START, StateGraph
from langgraph.types import Send

from ocr_api.insight_curator import (
    ALLOWED_TYPES,
    CRITIC_SYSTEM_PROMPT,
    CuratedInsightOut,
    CurateInsightsResponse,
    InsightCandidateIn,
    run_critic,
    template_fallback,
)
from ocr_api.insights.insight_router import route_candidates
from ocr_api.insights.prefilter import prefilter_candidates
from ocr_api.insights.specialist_agents import run_specialist
from ocr_api.insights.visualization_agent import attach_visualizations
from ocr_api.receipt_understanding import ReceiptUnderstandingError

logger = logging.getLogger("ocr_api.insights.graph")

_CRITIC_OVER_DRAFTS_PROMPT = CRITIC_SYSTEM_PROMPT


class InsightGraphState(TypedDict, total=False):
    raw_candidates: list[InsightCandidateIn]
    signals: list[InsightCandidateIn]
    selected_agents: list[str]
    agent_signals: dict[str, list[InsightCandidateIn]]
    dismissed_fact_keys: list[str]
    dismiss_counts: dict[str, int]
    # Reducer-merged list so parallel specialist branches accumulate drafts
    # instead of clobbering each other (the highest-risk Phase 3 bug).
    candidate_insights: Annotated[list[InsightCandidateIn], operator.add]
    final_insights: list[CuratedInsightOut]
    use_llm: bool
    use_specialists: bool
    engagement_weights: dict[str, float]


class SpecialistState(TypedDict, total=False):
    agent: str
    signals: list[InsightCandidateIn]
    use_llm: bool


def signal_loader(state: InsightGraphState) -> dict[str, Any]:
    raw = state.get("raw_candidates") or []
    sanitized = [c for c in raw if c.type in ALLOWED_TYPES and c.fact_key][:20]
    filtered = prefilter_candidates(
        sanitized,
        dismissed_fact_keys=state.get("dismissed_fact_keys"),
        dismiss_counts=state.get("dismiss_counts"),
    )
    return {
        "signals": filtered,
        "candidate_insights": [],
        "final_insights": [],
        "selected_agents": [],
        "agent_signals": {},
    }


def router_node(state: InsightGraphState) -> dict[str, Any]:
    decision = route_candidates(
        state.get("signals") or [],
        engagement_weights=state.get("engagement_weights"),
        dismiss_counts=state.get("dismiss_counts"),
    )
    agent_signals = {
        agent: decision.signals_for(agent) for agent in decision.selected_agents
    }
    return {
        "selected_agents": decision.selected_agents,
        "agent_signals": agent_signals,
        # When specialists are off, seed drafts with the eligible pool so
        # Critic still has something to rewrite (Phase 2 path).
        "candidate_insights": (
            []
            if state.get("use_specialists")
            else [r.candidate for r in decision.eligible]
        ),
    }


def _after_router(state: InsightGraphState) -> list[Send] | str:
    agents = state.get("selected_agents") or []
    if not agents:
        return END
    if not state.get("use_specialists"):
        return "critic"
    return [
        Send(
            "specialist",
            {
                "agent": agent,
                "signals": (state.get("agent_signals") or {}).get(agent, []),
                "use_llm": bool(state.get("use_llm", True)),
            },
        )
        for agent in agents
    ]


async def specialist_node(
    state: SpecialistState, config: RunnableConfig
) -> dict[str, Any]:
    """One specialist branch. Errors degrade to empty contribution."""
    http_client: httpx.AsyncClient = config["configurable"]["http_client"]
    agent = state.get("agent") or ""
    signals = state.get("signals") or []
    use_llm = bool(state.get("use_llm", True))
    try:
        drafts = await run_specialist(
            agent, signals, http_client=http_client, use_llm=use_llm
        )
    except Exception:
        logger.exception("specialist node %s crashed — empty contribution", agent)
        drafts = []
    return {"candidate_insights": drafts}


async def critic_node(
    state: InsightGraphState, config: RunnableConfig
) -> dict[str, Any]:
    http_client: httpx.AsyncClient = config["configurable"]["http_client"]
    drafts = state.get("candidate_insights") or []
    use_llm = bool(state.get("use_llm", True))
    if not drafts:
        return {"final_insights": []}

    prompt = _CRITIC_OVER_DRAFTS_PROMPT if state.get("use_specialists") else None
    try:
        result = await run_critic(
            drafts,
            http_client=http_client,
            use_llm=use_llm,
            system_prompt=prompt,
            dismissed_fact_keys=state.get("dismissed_fact_keys"),
            dismiss_counts=state.get("dismiss_counts"),
        )
    except ReceiptUnderstandingError:
        logger.exception("critic LLM failed — template fallback")
        result = template_fallback(drafts)
    return {"final_insights": result.insights}


def visualization_node(state: InsightGraphState) -> dict[str, Any]:
    """Visualization Story Agent: attach a visual spec to each final insight.

    Rule-based (not an LLM) — see visualization_agent.py. Runs after Critic
    so it only does work for the <=3 insights that survived dedupe/rank,
    not every raw candidate.
    """
    final_insights = state.get("final_insights") or []
    if not final_insights:
        return {"final_insights": final_insights}
    facts_by_key = {c.fact_key: c.facts for c in state.get("candidate_insights") or []}
    return {"final_insights": attach_visualizations(final_insights, facts_by_key)}


def build_insight_graph():
    """Compile the curation graph. Safe to call once and reuse."""
    g = StateGraph(InsightGraphState)
    g.add_node("signal_loader", signal_loader)
    g.add_node("router", router_node)
    g.add_node("specialist", specialist_node)
    g.add_node("critic", critic_node)
    g.add_node("visualization", visualization_node)

    g.add_edge(START, "signal_loader")
    g.add_edge("signal_loader", "router")
    g.add_conditional_edges("router", _after_router, ["critic", "specialist", END])
    g.add_edge("specialist", "critic")
    g.add_edge("critic", "visualization")
    g.add_edge("visualization", END)
    return g.compile()


_compiled = None


def get_insight_graph():
    global _compiled
    if _compiled is None:
        _compiled = build_insight_graph()
    return _compiled


async def run_insight_graph(
    candidates: list[InsightCandidateIn],
    *,
    http_client: httpx.AsyncClient,
    use_llm: bool = True,
    use_specialists: bool = False,
    engagement_weights: dict[str, float] | None = None,
    dismissed_fact_keys: list[str] | None = None,
    dismiss_counts: dict[str, int] | None = None,
) -> CurateInsightsResponse:
    """Public entry point used by POST /curate-insights."""
    graph = get_insight_graph()
    result = await graph.ainvoke(
        {
            "raw_candidates": candidates,
            "use_llm": use_llm,
            "use_specialists": use_specialists,
            "engagement_weights": engagement_weights or {},
            "dismissed_fact_keys": dismissed_fact_keys or [],
            "dismiss_counts": dismiss_counts or {},
            "candidate_insights": [],
            "final_insights": [],
            "signals": [],
            "selected_agents": [],
            "agent_signals": {},
        },
        config={"configurable": {"http_client": http_client}},
    )
    return CurateInsightsResponse(insights=result.get("final_insights") or [])
