from pydantic import BaseModel

from ocr_api.receipt_understanding import ReceiptUnderstandingResponse


class OcrWord(BaseModel):
    """One OCR word with calibrated confidence and geometry.

    Attached selectively to low-confidence lines (see OcrLine.words) so
    well-scanned receipts stay near the old payload size.
    """

    text: str
    confidence: float
    digit_corrected: bool = False
    left_ratio: float = 0.0
    width_ratio: float = 0.0


class OcrLine(BaseModel):
    text: str
    height_ratio: float
    left_ratio: float = 0.0
    top_ratio: float = 0.0
    width_ratio: float = 0.0
    # Calibrated line-level OCR confidence (0..1). Optional/additive so older
    # clients ignore it; None when TOKEN_LEVEL_CONFIDENCE is off.
    confidence: float | None = None
    # Per-word detail — only populated when this line's confidence is below
    # the enrichment threshold (and the feature flag is on). None otherwise.
    words: list[OcrWord] | None = None


class OcrResponse(BaseModel):
    text: str
    confidence: float
    # Per-line text + visual-prominence + bbox ratios (height/left/top/width
    # as fractions of image size), for merchant ranking and layout zone
    # classification on the client. Index-aligned with `text.split("\n")`.
    # None only in principle (the route always populates it); optional so an
    # older client reading just text/confidence is unaffected.
    lines: list[OcrLine] | None = None
    # LLM receipt-understanding, run synchronously in the same /ocr request
    # (see ocr_api/main.py) — None when OCR produced no text, or when the LLM
    # call itself failed (see understanding_error). A failed/missing
    # understanding never fails the /ocr request: raw OCR fields above are
    # always usable on their own.
    understanding: ReceiptUnderstandingResponse | None = None
    understanding_error: str | None = None
    # Adaptive OCR strategy telemetry (additive/optional). Populated when
    # ADAPTIVE_OCR_ENABLED=1; None on the legacy path so older clients and
    # the schema-stability contract stay backward-compatible for required keys.
    strategy_psm: str | None = None
    strategy_bucket: str | None = None
    pass_count: int | None = None
    composite_score: float | None = None
