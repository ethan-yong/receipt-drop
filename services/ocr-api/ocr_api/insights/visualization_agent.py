"""Rule-based Visualization Story Agent (not an LLM).

Decides, per curated insight, whether a small focused visual would strengthen
it — one insight, one visual story, never a dashboard. The mapping from
insight type to visualization/animation is a closed lookup table, not a
judgment call, so this stays deterministic like `insight_router.py` rather
than costing an LLM call.

Runs after the Critic (only on the <=3 insights that survive dedupe/rank),
before persistence.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from ocr_api.insight_curator import CuratedInsightOut

# Each rule's "parameters"/"highlight" values are fact keys to copy from the
# candidate's `facts` dict, not literal values — see build_visualization().
_VIZ_RULES: dict[str, dict[str, Any]] = {
    "spending_spike": {
        "type": "line_trend",
        "data_source": "weekday_spend_trend",
        "parameter_keys": {
            "weekday": "weekday",
            "baseline": "baseline",
            "today_total": "today_total",
        },
        "highlight": {"metric": "multiplier", "focus": "today"},
        "animation": {"type": "line_draw", "duration_ms": 900},
    },
    "category_shift": {
        "type": "before_after_bar",
        "data_source": "weekly_category_totals",
        "parameter_keys": {
            "category": "category",
            "previous": "last_week",
            "current": "this_week",
        },
        "highlight": {"metric": "percent_change", "focus": "current"},
        "animation": {"type": "bars_grow", "duration_ms": 700},
    },
    "habit": {
        "type": "habit_timeline",
        "data_source": "place_visit_frequency",
        "parameter_keys": {
            "place_name": "place_name",
            "visits": "visits",
            "window_days": "window_days",
        },
        "highlight": {"metric": "visits", "focus": "latest"},
        "animation": {"type": "icons_pop", "duration_ms": 600},
    },
    "forecast": {
        "type": "forecast_projection",
        "data_source": "month_pace_forecast",
        "parameter_keys": {
            "prior_month": "prior_month",
            "current_so_far": "current_so_far",
            "projected": "projected",
        },
        "highlight": {"metric": "percent_over", "focus": "projected"},
        "animation": {"type": "forecast_reveal", "duration_ms": 900},
    },
    # streak: the achievement system already handles motivation, and there is
    # no "meaningful history" signal in facts to gate on — default to none.
}


def build_visualization(
    insight_type: str, facts: dict[str, Any]
) -> dict[str, Any] | None:
    """Return a visualization spec for this insight, or None if not useful.

    Never fabricates: if a required fact key is missing, the visualization
    is dropped rather than emitted with a placeholder.
    """
    rule = _VIZ_RULES.get(insight_type)
    if rule is None:
        return None

    facts = facts or {}
    parameters: dict[str, Any] = {}
    for param_name, fact_key in rule["parameter_keys"].items():
        if fact_key not in facts:
            return None
        parameters[param_name] = facts[fact_key]

    return {
        "type": rule["type"],
        "data_source": rule["data_source"],
        "parameters": parameters,
        "highlight": dict(rule["highlight"]),
        "animation": dict(rule["animation"]),
    }


def attach_visualizations(
    insights: list[CuratedInsightOut],
    facts_by_key: dict[str, dict[str, Any]],
) -> list[CuratedInsightOut]:
    """Return a new list with `.visualization` populated on each insight."""
    out = []
    for insight in insights:
        facts = facts_by_key.get(insight.fact_key, {})
        visualization = build_visualization(insight.type, facts)
        out.append(insight.model_copy(update={"visualization": visualization}))
    return out
