"""Keyword-weight receipt classifier.

Scans lowercase OCR text for type-specific signals and returns a
ClassificationResult. No LLM call — runs in < 1 ms before the single
extraction call in call_receipt_understanding().

Fallback is "restaurant" (not "unknown") because restaurant is the
prior-probability winner in the Malaysian receipt corpus.
"""

from __future__ import annotations

from dataclasses import dataclass

# Each entry is (keyword_substring, weight).  Longer/more-specific phrases
# score higher so "transaction id" beats a stray "balance" hit.
_SIGNALS: dict[str, list[tuple[str, float]]] = {
    "payment": [
        ("touch n go", 3.0),
        ("tng ewallet", 3.0),
        ("tng wallet", 3.0),
        ("maybank", 3.0),
        ("maybank2u", 3.0),
        ("grabpay", 3.0),
        ("payment successful", 3.0),
        ("payment received", 3.0),
        ("transaction id", 2.5),
        ("transaction no", 2.5),
        ("reference no", 2.0),
        ("ref no", 1.5),
        ("transfer", 2.0),
        ("balance rm", 1.5),
        ("available balance", 2.0),
        ("account balance", 2.0),
        ("boost", 2.0),
        ("shopee pay", 2.5),
        ("duitnow", 2.5),
        ("fpx", 2.0),
    ],
    "transport": [
        ("booking reference", 3.0),
        ("booking ref", 3.0),
        ("pnr", 2.5),
        ("flight", 3.0),
        ("airline", 3.0),
        ("airasia", 3.0),
        ("malindo", 3.0),
        ("batik air", 3.0),
        ("departure", 2.5),
        ("arrival", 2.0),
        ("grab ride", 3.0),
        ("grab car", 3.0),
        ("grab express", 2.5),
        ("ktm", 2.0),
        ("lrt", 2.0),
        ("mrt", 2.0),
        ("express bus", 2.5),
        ("transit", 1.5),
        ("origin", 1.5),
        ("destination", 1.5),
        ("seat no", 2.0),
        ("gate", 1.5),
    ],
    "grocery": [
        ("qty", 2.5),
        ("quantity", 2.0),
        ("barcode", 2.0),
        ("supermarket", 3.0),
        ("hypermarket", 3.0),
        ("jaya grocer", 3.0),
        ("cold storage", 3.0),
        ("99 speedmart", 3.0),
        ("mydin", 3.0),
        ("hero market", 3.0),
        ("tesco", 3.0),
        ("aeon", 2.5),
        ("giant", 2.5),
        ("lotus", 2.0),
        ("village grocer", 3.0),
        ("member savings", 2.5),
        ("points earned", 2.0),
        ("gst", 1.0),
        ("sst", 1.0),
    ],
    "cafe": [
        ("kopitiam", 3.0),
        ("coffee bean", 3.0),
        ("starbucks", 3.0),
        ("old town white coffee", 3.0),
        ("old town", 2.0),
        ("zus coffee", 3.0),
        ("gigi coffee", 2.5),
        ("tealive", 3.0),
        ("chatime", 3.0),
        ("boba", 2.0),
        ("bubble tea", 2.5),
        ("americano", 2.0),
        ("latte", 2.0),
        ("cappuccino", 2.0),
        ("espresso", 2.0),
        ("affogato", 2.0),
    ],
    "restaurant": [
        ("restoran", 3.0),
        ("restaurant", 2.0),
        ("warung", 2.5),
        ("mamak", 2.5),
        ("nasi", 1.5),
        ("mee", 1.5),
        ("rice", 1.5),
        ("chicken", 1.0),
        ("table no", 2.0),
        ("table:", 1.5),
        ("pax", 1.5),
        ("cover charge", 2.0),
        ("service charge", 2.0),
    ],
}

# Minimum total weight needed to trust a classification. Below this the
# text has too few signals and we fall back to the restaurant default.
# Set low (0.08) because the grocery list has many brand-name entries that
# inflate the denominator; even a strong hit like "jaya grocer" + "qty"
# only scores ~0.13 against the full grocery weight total.
_MIN_CONFIDENCE_THRESHOLD = 0.08


@dataclass(frozen=True)
class ClassificationResult:
    receipt_type: str
    confidence: float  # 0-1, derived from normalised signal score


def classify_receipt(ocr_text: str) -> ClassificationResult:
    """Classify receipt type from raw OCR text.

    Returns a ClassificationResult with receipt_type and a confidence
    score in [0, 1].  Falls back to receipt_type="restaurant" when no
    type scores above the minimum threshold.
    """
    text = ocr_text.lower()
    scores: dict[str, float] = {}

    for receipt_type, signals in _SIGNALS.items():
        total_weight = sum(w for _, w in signals)
        hit_weight = sum(w for kw, w in signals if kw in text)
        scores[receipt_type] = hit_weight / total_weight if total_weight else 0.0

    best_type = max(scores, key=lambda t: scores[t])
    best_score = scores[best_type]

    if best_score < _MIN_CONFIDENCE_THRESHOLD:
        return ClassificationResult(receipt_type="restaurant", confidence=best_score)

    # Clamp to [0, 1] and scale so a max-match is ~0.99.
    confidence = min(best_score * 3.0, 0.99)
    return ClassificationResult(receipt_type=best_type, confidence=confidence)
