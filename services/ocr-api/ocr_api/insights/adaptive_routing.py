"""Engagement-weighted routing helpers (Phase 4).

Derives per-insight-type weights from dismiss history. Supports dismiss_counts
keyed by fact_key (client) or insight_type (legacy).
"""

from __future__ import annotations

from ocr_api.insights.insight_router import SIGNAL_TO_AGENT

_DEFAULT_WEIGHT = 1.0
_MIN_WEIGHT = 0.25

# fact_key prefix → insight type (matches lib/domain/logic/insight_detectors.dart).
_FACT_PREFIX_TO_TYPE: dict[str, str] = {
    "spike": "spending_spike",
    "shift": "category_shift",
    "habit": "habit",
    "streak": "streak",
    "forecast": "forecast",
}


def type_from_fact_key(fact_key: str) -> str | None:
    prefix = fact_key.split(":", 1)[0] if fact_key else ""
    if prefix in _FACT_PREFIX_TO_TYPE:
        return _FACT_PREFIX_TO_TYPE[prefix]
    if prefix in SIGNAL_TO_AGENT:
        return prefix
    return None


def type_dismiss_counts_from_fact_keys(
    dismiss_counts: dict[str, int],
) -> dict[str, int]:
    """Aggregate fact_key dismiss counts into per-type totals."""
    out: dict[str, int] = {typ: 0 for typ in SIGNAL_TO_AGENT}
    for key, count in dismiss_counts.items():
        if key in SIGNAL_TO_AGENT:
            out[key] = out.get(key, 0) + count
            continue
        typ = type_from_fact_key(key)
        if typ is not None:
            out[typ] = out.get(typ, 0) + count
    return out


def engagement_weights_from_type_dismiss_counts(
    dismiss_counts: dict[str, int],
    *,
    soft_threshold: int = 3,
) -> dict[str, float]:
    """Map insight_type → weight in [_MIN_WEIGHT, 1.0]."""
    weights: dict[str, float] = {typ: _DEFAULT_WEIGHT for typ in SIGNAL_TO_AGENT}
    for typ, count in dismiss_counts.items():
        if typ not in weights:
            continue
        if count < soft_threshold:
            continue
        excess = count - soft_threshold + 1
        decay = min(0.75, 0.15 * excess)
        weights[typ] = max(_MIN_WEIGHT, _DEFAULT_WEIGHT - decay)
    return weights


def engagement_weights_from_dismiss_counts(
    dismiss_counts: dict[str, int],
    *,
    soft_threshold: int = 3,
) -> dict[str, float]:
    """Backward-compatible entry: accepts fact_key or type keys."""
    if not dismiss_counts:
        return {typ: _DEFAULT_WEIGHT for typ in SIGNAL_TO_AGENT}
    # If keys look like fact_keys (contain ':'), aggregate by type first.
    if any(":" in k for k in dismiss_counts):
        type_counts = type_dismiss_counts_from_fact_keys(dismiss_counts)
        return engagement_weights_from_type_dismiss_counts(
            type_counts, soft_threshold=soft_threshold
        )
    return engagement_weights_from_type_dismiss_counts(
        dismiss_counts, soft_threshold=soft_threshold
    )
