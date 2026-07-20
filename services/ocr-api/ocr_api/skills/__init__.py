"""Receipt-type skills: keyword orchestrator + per-type extraction prompts.

Usage in receipt_understanding.py:
    from ocr_api.skills import classify_receipt, SKILL_PROMPTS
    classification = classify_receipt(ocr_text)
    prompt = SKILL_PROMPTS[classification.receipt_type]
"""

from ocr_api.skills.grocery import SYSTEM_PROMPT as GROCERY_PROMPT
from ocr_api.skills.orchestrator import ClassificationResult, classify_receipt
from ocr_api.skills.payment import SYSTEM_PROMPT as PAYMENT_PROMPT
from ocr_api.skills.restaurant import SYSTEM_PROMPT as RESTAURANT_PROMPT
from ocr_api.skills.transport import SYSTEM_PROMPT as TRANSPORT_PROMPT

RECEIPT_TYPES = [
    "restaurant",
    "cafe",
    "payment",
    "grocery",
    "retail",
    "transport",
    "travel",
    "unknown",
]

# Map receipt_type → extraction system prompt.
# "cafe" and "retail" share the restaurant/grocery prompt respectively
# (they differ mainly in classification, not extraction needs).
# "travel" shares the transport prompt.
# "unknown" falls back to the restaurant prompt as the safest default.
SKILL_PROMPTS: dict[str, str] = {
    "restaurant": RESTAURANT_PROMPT,
    "cafe": RESTAURANT_PROMPT,
    "payment": PAYMENT_PROMPT,
    "grocery": GROCERY_PROMPT,
    "retail": GROCERY_PROMPT,
    "transport": TRANSPORT_PROMPT,
    "travel": TRANSPORT_PROMPT,
    "unknown": RESTAURANT_PROMPT,
}

__all__ = [
    "ClassificationResult",
    "classify_receipt",
    "RECEIPT_TYPES",
    "SKILL_PROMPTS",
]
