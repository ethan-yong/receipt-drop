"""Phase 4: engagement-weighted routing helpers.

Derives per-insight-type weights from dismiss history already present on
`spending_insights` (dismissed + insight_type). Kept rule-based — no LLM
orchestrator. The Edge Function / client can eventually pass dismiss counts
into /curate-insights; until then this module is ready to consume that
payload via `engagement_weights_from_dismiss_counts`.
"""

from __future__ import annotations

from ocr_api.insights.insight_router import SIGNAL_TO_AGENT

# Types that the user has dismissed many times get a lower weight so the
# router is less likely to clear the severity floor for them.
_DEFAULT_WEIGHT = 1.0
_MIN_WEIGHT = 0.25


def engagement_weights_from_dismiss_counts(
    dismiss_counts: dict[str, int],
    *,
    soft_threshold: int = 3,
) -> dict[str, float]:
    """Map insight_type → weight in [_MIN_WEIGHT, 1.0].

    `dismiss_counts` keys are insight_type strings (spending_spike, …).
    Types with fewer than `soft_threshold` dismissals keep weight 1.0.
    Beyond that, weight decays linearly toward _MIN_WEIGHT.
    """
    weights: dict[str, float] = {typ: _DEFAULT_WEIGHT for typ in SIGNAL_TO_AGENT}
    for typ, count in dismiss_counts.items():
        if typ not in weights:
            continue
        if count < soft_threshold:
            continue
        # At soft_threshold → ~0.75; grows dismissals → approaches _MIN_WEIGHT.
        excess = count - soft_threshold + 1
        decay = min(0.75, 0.15 * excess)
        weights[typ] = max(_MIN_WEIGHT, _DEFAULT_WEIGHT - decay)
    return weights
