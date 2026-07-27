"""Composite OCR-pass scorer for adaptive strategy selection.

Scores a single Tesseract pass's output using cheap regex/string signals —
no LLM call. Used to decide whether a retry is warranted and which of two
passes to keep, generalizing today's confidence-only comparison.

Keyword list deliberately mirrors (does not call into) the Dart-side hints in
`lib/domain/logic/rm_amount_parser.dart` (`totalKeywordHints` /
`discountOrSummaryHints`) and the footer-ish terms used by
`receipt_layout_analyzer.dart`. A third, related keyword list already lives
in `ocr_api/skills/orchestrator.py` (post-OCR receipt-*type* classification) —
adding a new receipt keyword should be considered in all three places.

The RM-amount regex below mirrors `ocr_engine._RM_AMOUNT_RE` (kept local to
avoid a circular import with `ocr_engine`, which calls into this module).
"""

from __future__ import annotations

import logging
import os
import re
from dataclasses import dataclass
from typing import Protocol

logger = logging.getLogger("ocr_api.ocr_scoring")

# Mirrors ocr_engine._RM_AMOUNT_RE — keep in sync when that pattern changes.
_RM_AMOUNT_RE = re.compile(r"(RM\s{0,3})([0-9ZzOlI]+(?:\.[0-9ZzOlI]{1,2})?)")

# Mirrored from Dart totalKeywordHints + discountOrSummaryHints + common
# receipt boilerplate — keep in sync when those Dart lists change.
_RECEIPT_KEYWORDS = re.compile(
    r"(total|subtotal|amount\s*due|jumlah|bayaran|pembayaran|"
    r"wang\s*diterima|amaun\s*dibayar|tax|cukai|gst|sst|"
    r"\bcash\b|change|baki|tunai|diskaun|discount|"
    r"receipt|invoice|thank\s*you|\brm\b)",
    re.IGNORECASE,
)

_TOKEN_RE = re.compile(r"[A-Za-z0-9]+(?:\.[0-9]{1,2})?")
_SYMBOL_HEAVY_RE = re.compile(r"^[^A-Za-z0-9]*$")
_ALPHA_HEAVY_RE = re.compile(r"[A-Za-z]{3,}")

# Provisional weights — tune via scripts/process_receipts.ps1 before default-on.
_DEFAULT_WEIGHTS = {
    "confidence": 0.40,
    "amount": 0.20,
    "keywords": 0.15,
    "coherence": 0.15,
    "line_count": 0.05,
    "merchant": 0.05,
}
_DEFAULT_GOOD_ENOUGH = 0.45


class _HasText(Protocol):
    text: str


def _safe_float_env(name: str, default: float) -> float:
    raw = os.environ.get(name)
    if raw is None or raw.strip() == "":
        return default
    try:
        return float(raw)
    except ValueError:
        logger.warning("invalid %s=%r — using default %.4f", name, raw, default)
        return default


def _weights() -> dict[str, float]:
    return {
        key: _safe_float_env(f"ADAPTIVE_OCR_WEIGHT_{key.upper()}", default)
        for key, default in _DEFAULT_WEIGHTS.items()
    }


def good_enough_threshold() -> float:
    return _safe_float_env("ADAPTIVE_OCR_GOOD_ENOUGH_SCORE", _DEFAULT_GOOD_ENOUGH)


@dataclass(frozen=True)
class ScoreBreakdown:
    confidence: float
    amount: float
    keywords: float
    coherence: float
    line_count: float
    merchant: float
    total: float


def _amount_signal(text: str) -> float:
    return 1.0 if _RM_AMOUNT_RE.search(text) else 0.0


def _keyword_signal(text: str) -> float:
    hits = len(_RECEIPT_KEYWORDS.findall(text))
    # Saturate quickly — 3+ hits is a strong receipt signal.
    return min(1.0, hits / 3.0)


def _coherence_signal(text: str) -> float:
    tokens = text.split()
    if not tokens:
        return 0.0
    plausible = 0
    for tok in tokens:
        if _SYMBOL_HEAVY_RE.match(tok):
            continue
        if _TOKEN_RE.fullmatch(tok) or _ALPHA_HEAVY_RE.search(tok):
            plausible += 1
    return plausible / len(tokens)


def _line_count_signal(line_count: int, image_height: int | None) -> float:
    if line_count <= 0:
        return 0.0
    if not image_height or image_height <= 0:
        if line_count < 2:
            return 0.3
        if line_count > 120:
            return 0.2
        return 1.0
    expected_min = max(2, image_height // 80)
    expected_max = max(expected_min + 5, image_height // 15)
    if line_count < expected_min:
        return max(0.0, line_count / expected_min)
    if line_count > expected_max:
        over = line_count / expected_max
        return max(0.0, 1.0 / over)
    return 1.0


def _merchant_proxy_signal(lines: list[_HasText]) -> float:
    """Cheap header-like line in the first few recognized lines."""
    for line in lines[:5]:
        text = line.text.strip()
        if len(text) < 3:
            continue
        letters = sum(1 for c in text if c.isalpha())
        if letters >= 4 and letters / max(len(text), 1) >= 0.5:
            return 1.0
    return 0.0


def score_ocr_pass(
    lines: list[_HasText],
    confidence: float,
    *,
    image_height: int | None = None,
) -> ScoreBreakdown:
    """Return a 0–1 composite score and per-component breakdown."""
    text = "\n".join(line.text for line in lines)
    weights = _weights()
    components = {
        "confidence": max(0.0, min(1.0, confidence)),
        "amount": _amount_signal(text),
        "keywords": _keyword_signal(text),
        "coherence": _coherence_signal(text),
        "line_count": _line_count_signal(len(lines), image_height),
        "merchant": _merchant_proxy_signal(lines),
    }
    total = max(0.0, min(1.0, sum(components[k] * weights[k] for k in weights)))
    return ScoreBreakdown(
        confidence=components["confidence"],
        amount=components["amount"],
        keywords=components["keywords"],
        coherence=components["coherence"],
        line_count=components["line_count"],
        merchant=components["merchant"],
        total=total,
    )
