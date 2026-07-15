from pydantic import BaseModel

from ocr_api.receipt_understanding import ReceiptUnderstandingResponse


class OcrLine(BaseModel):
    text: str
    height_ratio: float


class OcrResponse(BaseModel):
    text: str
    confidence: float
    # Per-line text + visual-prominence data (median word bbox height /
    # image height), for merchant-candidate ranking on the client. None only
    # in principle (the route always populates it); optional so an older
    # client reading just text/confidence is unaffected.
    lines: list[OcrLine] | None = None
    # LLM receipt-understanding, run synchronously in the same /ocr request
    # (see ocr_api/main.py) — None when OCR produced no text, or when the LLM
    # call itself failed (see understanding_error). A failed/missing
    # understanding never fails the /ocr request: raw OCR fields above are
    # always usable on their own.
    understanding: ReceiptUnderstandingResponse | None = None
    understanding_error: str | None = None
