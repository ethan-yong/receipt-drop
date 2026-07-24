"""Unit tests for the composite OCR-pass scorer."""

from __future__ import annotations

from dataclasses import dataclass

import pytest

from ocr_api.ocr_scoring import good_enough_threshold, score_ocr_pass


@dataclass(frozen=True)
class _Line:
    text: str


def test_good_enough_threshold_default() -> None:
    assert 0.0 < good_enough_threshold() < 1.0


def test_good_enough_threshold_fails_safe_on_bad_env(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("ADAPTIVE_OCR_GOOD_ENOUGH_SCORE", "not-a-float")
    assert good_enough_threshold() == pytest.approx(0.45)


def test_score_rewards_amount_and_keywords() -> None:
    lines = [
        _Line("RESTORAN ANWAR"),
        _Line("NASI LEMAK RM 7.50"),
        _Line("TOTAL RM 7.50"),
    ]
    score = score_ocr_pass(lines, confidence=0.7)
    assert score.amount == 1.0
    assert score.keywords > 0
    assert score.merchant == 1.0
    assert score.total > 0.5


def test_score_penalizes_incoherent_high_confidence_garbage() -> None:
    """Binarization can inflate confidence while destroying text fidelity.

    A high-confidence but symbol-noise result must score worse than a
    lower-confidence but coherent receipt — the failure mode confidence-only
    comparison couldn't catch.
    """
    garbage = [
        _Line("### @@ !!"),
        _Line("~~~~ ^^^^"),
        _Line("*** ###"),
    ]
    coherent = [
        _Line("SAMPLE STORE"),
        _Line("MILK RM 4.50"),
        _Line("TOTAL RM 7.70"),
    ]
    garbage_score = score_ocr_pass(garbage, confidence=0.95)
    coherent_score = score_ocr_pass(coherent, confidence=0.55)
    assert coherent_score.total > garbage_score.total
    assert garbage_score.coherence < 0.5
    assert coherent_score.amount == 1.0


def test_sparse_receipt_with_amount_not_penalized_for_missing_keywords() -> None:
    lines = [_Line("RM 12.00")]
    score = score_ocr_pass(lines, confidence=0.6)
    assert score.amount == 1.0
    # Must not hard-gate on keywords — amount alone should still contribute.
    assert score.total >= score.confidence * 0.4 + 0.20 * 0.9  # rough floor


def test_empty_lines_score_near_zero() -> None:
    score = score_ocr_pass([], confidence=0.0)
    assert score.total == pytest.approx(0.0)
