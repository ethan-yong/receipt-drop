"""Insight curation graph: rule-based router, LangGraph workflow, specialists.

Kept as a subpackage (mirroring ocr_api/skills/) so the insight-routing
module is never confused with skills/orchestrator.py (the keyword receipt
classifier).

Heavy imports (LangGraph graph) are lazy via __getattr__ so lightweight
modules like insight_router / adaptive_routing stay importable without
langchain_core being present yet during partial installs.
"""

from ocr_api.insights.adaptive_routing import engagement_weights_from_dismiss_counts
from ocr_api.insights.insight_router import (
    SIGNAL_TO_AGENT,
    RoutingDecision,
    route_candidates,
)

__all__ = [
    "SIGNAL_TO_AGENT",
    "RoutingDecision",
    "route_candidates",
    "run_insight_graph",
    "engagement_weights_from_dismiss_counts",
]


def __getattr__(name: str):
    if name == "run_insight_graph":
        from ocr_api.insights.graph import run_insight_graph

        return run_insight_graph
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
