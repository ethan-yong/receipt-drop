"""Tests for deterministic insight pre-filter."""

from ocr_api.insight_curator import InsightCandidateIn
from ocr_api.insights.prefilter import (
    MAX_CANDIDATES_TO_LLM,
    PREFILTER_SEVERITY_FLOOR,
    prefilter_candidates,
)


def _c(
    typ: str,
    fact_key: str,
    severity: float = 0.6,
    **facts,
) -> InsightCandidateIn:
    return InsightCandidateIn(
        type=typ,
        fact_key=fact_key,
        facts=facts,
        severity=severity,
        template_hint=f"hint {fact_key}",
    )


def test_dismissed_fact_key_hard_dropped():
    cands = [_c("habit", "habit:tealive:2026-07-28")]
    out = prefilter_candidates(
        cands,
        dismissed_fact_keys=["habit:tealive:2026-07-28"],
    )
    assert out == []


def test_soft_ban_requires_high_severity_to_resurface():
    cands = [_c("streak", "streak:3:2026-07-28", severity=0.5)]
    out = prefilter_candidates(
        cands,
        dismiss_counts={"streak:3:2026-07-28": 5},
    )
    assert out == []

    strong = [_c("streak", "streak:3:2026-07-28", severity=0.9)]
    out2 = prefilter_candidates(
        strong,
        dismiss_counts={"streak:3:2026-07-28": 5},
    )
    assert len(out2) == 1


def test_group_dedupe_keeps_highest_severity():
    cands = [
        _c("habit", "habit:tealive:2026-07-28", severity=0.5, place_name="Tealive"),
        _c("habit", "habit:tealive:2026-07-29", severity=0.8, place_name="Tealive"),
    ]
    out = prefilter_candidates(cands)
    assert len(out) == 1
    assert out[0].fact_key == "habit:tealive:2026-07-29"


def test_caps_at_max_candidates():
    cands = [
        _c("streak", f"streak:{i}:2026-07-28", severity=0.5 + i * 0.01)
        for i in range(10)
    ]
    out = prefilter_candidates(cands)
    assert len(out) <= MAX_CANDIDATES_TO_LLM


def test_below_floor_dropped():
    cands = [_c("forecast", "forecast:2026-07", severity=0.2)]
    out = prefilter_candidates(cands)
    assert out == []
    assert PREFILTER_SEVERITY_FLOOR == 0.45


def test_soft_dismiss_multiplier_halves_effective_severity():
    cands = [_c("habit", "habit:tealive:2026-07-28", severity=0.5)]
    out = prefilter_candidates(
        cands,
        dismiss_counts={"habit:tealive:2026-07-28": 3},
    )
    assert out == []
