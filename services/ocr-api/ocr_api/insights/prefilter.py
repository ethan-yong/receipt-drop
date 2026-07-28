"""Deterministic pre-filter before the Critic LLM call.

Reduces candidate count, applies dismiss personalization, and dedupes by
semantic group — cheap gatekeeping so the LLM sees at most four strong signals.
"""

from __future__ import annotations

from ocr_api.insight_curator import ALLOWED_TYPES, InsightCandidateIn
from ocr_api.insights.adaptive_routing import (
    engagement_weights_from_type_dismiss_counts,
    type_dismiss_counts_from_fact_keys,
)

PREFILTER_SEVERITY_FLOOR = 0.45
MAX_CANDIDATES_TO_LLM = 4
MAX_PER_TYPE = 2

SOFT_DISMISS_THRESHOLD = 3
SOFT_BAN_THRESHOLD = 5
SOFT_BAN_RESURFACE_SEVERITY = 0.85


def _entity_group(candidate: InsightCandidateIn) -> str:
    """Semantic group key for within-cycle dedupe."""
    facts = candidate.facts or {}
    entity = (
        facts.get("category")
        or facts.get("place_name")
        or facts.get("merchant")
        or facts.get("placeName")
    )
    if entity is not None:
        return f"{candidate.type}:{str(entity).lower()}"
    # Fall back to fact_key stem (drop trailing date segment when present).
    parts = candidate.fact_key.split(":")
    stem = ":".join(parts[:2]) if len(parts) >= 2 else candidate.fact_key
    return f"{candidate.type}:{stem.lower()}"


def _entity_group_from_fact_key(fact_key: str) -> str:
    parts = fact_key.split(":")
    if len(parts) >= 2:
        prefix = parts[0]
        typ = _TYPE_FROM_FACT_PREFIX.get(prefix, prefix)
        stem = ":".join(parts[:2])
        return f"{typ}:{stem.lower()}"
    return fact_key.lower()


_TYPE_FROM_FACT_PREFIX: dict[str, str] = {
    "spike": "spending_spike",
    "shift": "category_shift",
    "habit": "habit",
    "streak": "streak",
    "forecast": "forecast",
}


def _dismiss_multiplier(
    candidate: InsightCandidateIn,
    *,
    dismissed_fact_keys: set[str],
    dismiss_counts: dict[str, int],
    dismissed_entity_groups: set[str],
) -> float | None:
    """Return severity multiplier, or None if candidate should be hard-dropped."""
    fk = candidate.fact_key
    if fk in dismissed_fact_keys:
        return None

    count = dismiss_counts.get(fk, 0)
    if count >= SOFT_BAN_THRESHOLD:
        if candidate.severity < SOFT_BAN_RESURFACE_SEVERITY:
            return None
        # Significant resurface — allow through without soft-dismiss penalty.
        return 1.0
    if count >= SOFT_DISMISS_THRESHOLD:
        return 0.5

    group = _entity_group(candidate)
    if group in dismissed_entity_groups and candidate.severity < SOFT_BAN_RESURFACE_SEVERITY:
        return 0.4

    return 1.0


def prefilter_candidates(
    candidates: list[InsightCandidateIn],
    *,
    dismissed_fact_keys: list[str] | None = None,
    dismiss_counts: dict[str, int] | None = None,
) -> list[InsightCandidateIn]:
    """Return up to [MAX_CANDIDATES_TO_LLM] candidates for the Critic."""
    dismissed = set(dismissed_fact_keys or [])
    counts = dismiss_counts or {}
    dismissed_groups = {_entity_group_from_fact_key(fk) for fk in dismissed}

    type_counts = type_dismiss_counts_from_fact_keys(counts)
    type_weights = engagement_weights_from_type_dismiss_counts(type_counts)

    scored: list[tuple[float, InsightCandidateIn]] = []

    for c in candidates:
        if c.type not in ALLOWED_TYPES or not c.fact_key:
            continue

        mult = _dismiss_multiplier(
            c,
            dismissed_fact_keys=dismissed,
            dismiss_counts=counts,
            dismissed_entity_groups=dismissed_groups,
        )
        if mult is None:
            continue

        type_weight = type_weights.get(c.type, 1.0)
        effective = c.severity * mult * type_weight
        if effective < PREFILTER_SEVERITY_FLOOR:
            continue
        scored.append((effective, c))

    # Group dedupe: keep highest effective severity per entity group.
    best_by_group: dict[str, tuple[float, InsightCandidateIn]] = {}
    for eff, c in scored:
        group = _entity_group(c)
        prev = best_by_group.get(group)
        if prev is None or eff > prev[0]:
            best_by_group[group] = (eff, c)

    deduped = sorted(best_by_group.values(), key=lambda x: x[0], reverse=True)

    # Cap per type, then global cap.
    type_seen: dict[str, int] = {}
    out: list[InsightCandidateIn] = []
    for _eff, c in deduped:
        n = type_seen.get(c.type, 0)
        if n >= MAX_PER_TYPE:
            continue
        type_seen[c.type] = n + 1
        out.append(c)
        if len(out) >= MAX_CANDIDATES_TO_LLM:
            break

    return out
