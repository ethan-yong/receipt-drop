"""Unit tests for the rule-based Visualization Story Agent."""

from ocr_api.insight_curator import CuratedInsightOut
from ocr_api.insights.visualization_agent import (
    attach_visualizations,
    build_visualization,
)


def test_spending_spike_produces_line_trend():
    viz = build_visualization(
        "spending_spike",
        {
            "weekday": "Tuesday",
            "today_total": 80.0,
            "baseline": 20.0,
            "multiplier": 4.0,
        },
    )
    assert viz is not None
    assert viz["type"] == "line_trend"
    assert viz["parameters"] == {
        "weekday": "Tuesday",
        "baseline": 20.0,
        "today_total": 80.0,
    }
    assert viz["highlight"] == {"metric": "multiplier", "focus": "today"}
    assert viz["animation"] == {"type": "line_draw", "duration_ms": 900}


def test_category_shift_produces_before_after_bar():
    viz = build_visualization(
        "category_shift",
        {
            "category": "Food",
            "direction": "up",
            "this_week": 150.0,
            "last_week": 110.0,
            "percent_change": 35,
        },
    )
    assert viz is not None
    assert viz["type"] == "before_after_bar"
    assert viz["parameters"] == {
        "category": "Food",
        "previous": 110.0,
        "current": 150.0,
    }
    assert viz["animation"]["type"] == "bars_grow"


def test_habit_produces_habit_timeline():
    viz = build_visualization(
        "habit",
        {"place_name": "Tealive", "visits": 5, "window_days": 7, "total_spend": 40.0},
    )
    assert viz is not None
    assert viz["type"] == "habit_timeline"
    assert viz["parameters"] == {
        "place_name": "Tealive",
        "visits": 5,
        "window_days": 7,
    }


def test_forecast_produces_forecast_projection():
    viz = build_visualization(
        "forecast",
        {
            "projected": 500.0,
            "prior_month": 400.0,
            "current_so_far": 300.0,
            "percent_over": 25,
        },
    )
    assert viz is not None
    assert viz["type"] == "forecast_projection"
    assert viz["parameters"] == {
        "prior_month": 400.0,
        "current_so_far": 300.0,
        "projected": 500.0,
    }
    assert viz["animation"]["type"] == "forecast_reveal"


def test_streak_has_no_visualization():
    assert build_visualization("streak", {"streak_days": 7}) is None


def test_unknown_type_has_no_visualization():
    assert build_visualization("budget_warning", {"n": 1}) is None


def test_missing_required_fact_key_drops_visualization_rather_than_fabricate():
    # category_shift requires "category", "this_week", "last_week" — omit one.
    viz = build_visualization(
        "category_shift",
        {"direction": "up", "this_week": 150.0, "last_week": 110.0},
    )
    assert viz is None


def test_attach_visualizations_matches_by_fact_key():
    insights = [
        CuratedInsightOut(
            type="habit", fact_key="habit:tealive", body="You visit Tealive often."
        ),
        CuratedInsightOut(type="streak", fact_key="streak:7", body="7-day streak!"),
    ]
    facts_by_key = {
        "habit:tealive": {"place_name": "Tealive", "visits": 4, "window_days": 7},
        "streak:7": {"streak_days": 7},
    }
    out = attach_visualizations(insights, facts_by_key)
    by_key = {i.fact_key: i for i in out}
    assert by_key["habit:tealive"].visualization is not None
    assert by_key["habit:tealive"].visualization["type"] == "habit_timeline"
    assert by_key["streak:7"].visualization is None
    # Original list must be untouched (attach_visualizations returns copies).
    assert insights[0].visualization is None


def test_attach_visualizations_defaults_to_empty_facts_when_key_missing():
    insights = [
        CuratedInsightOut(type="habit", fact_key="habit:unknown", body="Something.")
    ]
    out = attach_visualizations(insights, {})
    assert out[0].visualization is None
