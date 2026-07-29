"""Tests for insight curator response validation."""

from ocr_api.insight_curator import (
    InsightCandidateIn,
    parse_curated_insights,
    template_fallback,
)


def _cands():
    return [
        InsightCandidateIn(
            type="streak",
            fact_key="streak:3:2026-07-28",
            facts={"streak_days": 3},
            severity=0.5,
            template_hint="You logged receipts 3 days in a row",
        ),
        InsightCandidateIn(
            type="habit",
            fact_key="habit:place:2026-07-28",
            facts={"place_name": "Tealive", "visits": 3},
            severity=0.4,
            template_hint="You visited Tealive 3 times",
        ),
    ]


def test_parse_accepts_valid_payload():
    raw = """
    {"insights":[
      {"type":"streak","fact_key":"streak:3:2026-07-28",
       "body":"Nice 3-day streak!"},
      {"type":"habit","fact_key":"habit:place:2026-07-28",
       "body":"Tealive is a regular stop."}
    ]}
    """
    parsed = parse_curated_insights(raw, _cands())
    assert parsed is not None
    assert len(parsed.insights) == 2
    assert parsed.insights[0].type == "streak"


def test_parse_accepts_title_description_format():
    raw = """
    {"insights":[
      {"type":"streak","fact_key":"streak:3:2026-07-28",
       "title":"Nice streak",
       "description":"You logged receipts 3 days in a row.",
       "priority":0.9}
    ]}
    """
    parsed = parse_curated_insights(raw, _cands())
    assert parsed is not None
    assert len(parsed.insights) == 1
    assert (
        parsed.insights[0].body == "Nice streak. You logged receipts 3 days in a row."
    )
    assert parsed.insights[0].priority == 0.9


def test_parse_rejects_invented_numbers():
    raw = """
    {"insights":[
      {"type":"streak","fact_key":"streak:3:2026-07-28",
       "description":"You had 99 days in a row"}
    ]}
    """
    assert parse_curated_insights(raw, _cands()) is None


def test_parse_rejects_unknown_type():
    raw = """
    {"insights":[
      {"type":"budget_warning","fact_key":"streak:3:2026-07-28",
       "body":"Stop spending"}
    ]}
    """
    assert parse_curated_insights(raw, _cands()) is None


def test_parse_rejects_fabricated_fact_key():
    raw = """
    {"insights":[
      {"type":"streak","fact_key":"made-up-key","body":"Invented fact"}
    ]}
    """
    assert parse_curated_insights(raw, _cands()) is None


def test_parse_rejects_type_fact_mismatch():
    raw = """
    {"insights":[
      {"type":"habit","fact_key":"streak:3:2026-07-28",
       "body":"Wrong type for key"}
    ]}
    """
    assert parse_curated_insights(raw, _cands()) is None


def test_parse_caps_at_three():
    cands = [
        InsightCandidateIn(
            type="streak",
            fact_key=f"streak:{i}",
            facts={"streak_days": i},
            severity=0.5,
            template_hint=f"streak {i}",
        )
        for i in range(5)
    ]
    raw = {
        "insights": [
            {"type": "streak", "fact_key": f"streak:{i}", "body": f"body {i}"}
            for i in range(5)
        ]
    }
    import json

    parsed = parse_curated_insights(json.dumps(raw), cands)
    assert parsed is not None
    assert len(parsed.insights) == 3


def test_template_fallback_uses_hints():
    result = template_fallback(_cands())
    assert len(result.insights) == 2
    assert "3 days" in result.insights[0].body
