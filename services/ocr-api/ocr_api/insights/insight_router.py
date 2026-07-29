"""Rule-based insight router (not an LLM).

Maps on-device InsightCandidate types to specialist agent names and applies a
severity floor before a signal is considered worth dispatching. Named
`insight_router` deliberately — ocr_api/skills/orchestrator.py is a different
concept (keyword receipt classifier for /understand).

Severity floor defaults to 0.3 to match the detector-side clamp in
lib/domain/logic/insight_detectors.dart (every detector either emits nothing
or emits severity >= 0.3).
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from ocr_api.insight_curator import InsightCandidateIn

logger = logging.getLogger("ocr_api.insights.insight_router")

# Closed vocabulary matching InsightCandidate.type / ALLOWED_TYPES.
SIGNAL_TO_AGENT: dict[str, str] = {
    "spending_spike": "spending_anomaly_agent",
    "category_shift": "category_behavior_agent",
    "habit": "merchant_habit_agent",
    "streak": "motivation_agent",
    "forecast": "forecast_agent",
}

# Raised from 0.3 — prefilter uses 0.45; router stays aligned for specialist path.
DEFAULT_SEVERITY_FLOOR = 0.45

SOFT_BAN_THRESHOLD = 5
SOFT_BAN_RESURFACE_SEVERITY = 0.85

# Optional per-type overrides (all equal to the default for now).
SEVERITY_FLOOR_BY_TYPE: dict[str, float] = {
    typ: DEFAULT_SEVERITY_FLOOR for typ in SIGNAL_TO_AGENT
}


@dataclass(frozen=True)
class RoutedSignal:
    """One candidate that cleared the severity floor, tagged with its agent."""

    agent: str
    candidate: InsightCandidateIn


@dataclass
class RoutingDecision:
    """Explicit, loggable routing artifact for one curation cycle."""

    selected_agents: list[str] = field(default_factory=list)
    eligible: list[RoutedSignal] = field(default_factory=list)
    dropped_below_floor: int = 0
    dropped_unknown_type: int = 0

    @property
    def is_empty(self) -> bool:
        return not self.selected_agents

    def signals_for(self, agent: str) -> list[InsightCandidateIn]:
        return [r.candidate for r in self.eligible if r.agent == agent]


def route_candidates(
    candidates: list[InsightCandidateIn],
    *,
    severity_floors: dict[str, float] | None = None,
    engagement_weights: dict[str, float] | None = None,
    dismiss_counts: dict[str, int] | None = None,
) -> RoutingDecision:
    """Tag candidates with specialist agent names; filter by severity floor.

    `engagement_weights` (Phase 4): optional per-insight-type multiplier in
    (0, 1]. Applied to severity before the floor check so consistently
    dismissed types can be deprioritized without an LLM orchestrator.
    Missing keys default to 1.0 (no change).
    """
    floors = severity_floors or SEVERITY_FLOOR_BY_TYPE
    weights = engagement_weights or {}
    counts = dismiss_counts or {}
    eligible: list[RoutedSignal] = []
    dropped_below = 0
    dropped_unknown = 0
    agents_seen: list[str] = []

    for c in candidates:
        agent = SIGNAL_TO_AGENT.get(c.type)
        if agent is None:
            dropped_unknown += 1
            continue
        dismiss_n = counts.get(c.fact_key, 0)
        if dismiss_n >= SOFT_BAN_THRESHOLD and c.severity < SOFT_BAN_RESURFACE_SEVERITY:
            dropped_below += 1
            continue
        floor = floors.get(c.type, DEFAULT_SEVERITY_FLOOR)
        weight = weights.get(c.type, 1.0)
        # Clamp weight to a sane range so a bad caller can't invert the gate.
        weight = max(0.0, min(weight, 1.0))
        effective = c.severity * weight
        if effective < floor:
            dropped_below += 1
            continue
        eligible.append(RoutedSignal(agent=agent, candidate=c))
        if agent not in agents_seen:
            agents_seen.append(agent)

    decision = RoutingDecision(
        selected_agents=agents_seen,
        eligible=eligible,
        dropped_below_floor=dropped_below,
        dropped_unknown_type=dropped_unknown,
    )
    logger.info(
        "insight_router: agents=%s eligible=%d dropped_floor=%d dropped_unknown=%d",
        decision.selected_agents,
        len(decision.eligible),
        decision.dropped_below_floor,
        decision.dropped_unknown_type,
    )
    return decision
