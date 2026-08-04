"""Unit tests for the rule-based insight router."""

from ocr_api.insight_curator import InsightCandidateIn
from ocr_api.insights.insight_router import (
    DEFAULT_SEVERITY_FLOOR,
    SIGNAL_TO_AGENT,
    route_candidates,
)


def _c(
    typ: str,
    fact_key: str,
    severity: float = 0.5,
) -> InsightCandidateIn:
    return InsightCandidateIn(
        type=typ,
        fact_key=fact_key,
        facts={},
        severity=severity,
        template_hint=f"hint for {fact_key}",
    )


def test_routes_each_known_type_to_its_agent():
    cands = [_c(t, f"k:{t}") for t in SIGNAL_TO_AGENT]
    decision = route_candidates(cands)
    assert set(decision.selected_agents) == set(SIGNAL_TO_AGENT.values())
    assert len(decision.eligible) == 5
    assert decision.dropped_below_floor == 0
    assert decision.dropped_unknown_type == 0


def test_empty_pool_yields_empty_decision():
    decision = route_candidates([])
    assert decision.is_empty
    assert decision.selected_agents == []
    assert decision.eligible == []


def test_sub_threshold_candidates_are_dropped():
    # Floor is 0.45; a 0.2 signal must not dispatch its agent.
    cands = [
        _c("streak", "streak:low", severity=0.2),
        _c("habit", "habit:ok", severity=0.5),
    ]
    decision = route_candidates(cands)
    assert decision.selected_agents == ["merchant_habit_agent"]
    assert len(decision.eligible) == 1
    assert decision.dropped_below_floor == 1
    assert decision.eligible[0].candidate.fact_key == "habit:ok"


def test_unknown_type_is_dropped():
    cands = [_c("budget_warning", "bad:1", severity=0.9)]
    decision = route_candidates(cands)
    assert decision.is_empty
    assert decision.dropped_unknown_type == 1


def test_severity_floor_raised_for_quality_gate():
    assert DEFAULT_SEVERITY_FLOOR == 0.45


def test_engagement_weight_can_drop_dismissed_type():
    # Weight 0.5 on a borderline streak drops it below the 0.45 floor.
    cands = [_c("streak", "streak:3", severity=0.5)]
    decision = route_candidates(cands, engagement_weights={"streak": 0.5})
    assert decision.is_empty
    assert decision.dropped_below_floor == 1


def test_signals_for_returns_only_that_agents_slice():
    cands = [
        _c("streak", "streak:1"),
        _c("habit", "habit:1"),
        _c("streak", "streak:2"),
    ]
    decision = route_candidates(cands)
    streak = decision.signals_for("motivation_agent")
    assert [c.fact_key for c in streak] == ["streak:1", "streak:2"]
    assert decision.signals_for("forecast_agent") == []


def test_soft_ban_drops_high_dismiss_count_unless_severe():
    cands = [_c("streak", "streak:3", severity=0.5)]
    decision = route_candidates(cands, dismiss_counts={"streak:3": 5})
    assert decision.is_empty
    assert decision.dropped_below_floor == 1

    strong = [_c("streak", "streak:3", severity=0.9)]
    decision2 = route_candidates(strong, dismiss_counts={"streak:3": 5})
    assert len(decision2.eligible) == 1
