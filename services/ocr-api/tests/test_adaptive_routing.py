"""Tests for Phase 4 engagement-weighted routing helpers."""

from ocr_api.insights.adaptive_routing import engagement_weights_from_dismiss_counts
from ocr_api.insights.insight_router import SIGNAL_TO_AGENT


def test_no_dismissals_keeps_all_weights_at_one():
    weights = engagement_weights_from_dismiss_counts({})
    assert set(weights) == set(SIGNAL_TO_AGENT)
    assert all(w == 1.0 for w in weights.values())


def test_below_threshold_unchanged():
    weights = engagement_weights_from_dismiss_counts({"streak": 2}, soft_threshold=3)
    assert weights["streak"] == 1.0


def test_at_and_above_threshold_decays():
    weights = engagement_weights_from_dismiss_counts({"streak": 3}, soft_threshold=3)
    assert weights["streak"] < 1.0
    assert weights["streak"] >= 0.25
    assert weights["habit"] == 1.0


def test_heavy_dismissals_floor_at_min():
    weights = engagement_weights_from_dismiss_counts(
        {"forecast": 100}, soft_threshold=3
    )
    assert weights["forecast"] == 0.25


def test_fact_key_dismiss_counts_aggregate_to_type_weights():
    weights = engagement_weights_from_dismiss_counts(
        {
            "streak:1:2026-07-28": 3,
            "streak:2:2026-07-28": 2,
        }
    )
    assert weights["streak"] < 1.0
    assert weights["habit"] == 1.0


def test_unknown_type_ignored():
    weights = engagement_weights_from_dismiss_counts({"not_a_type": 99})
    assert "not_a_type" not in weights
