from pydantic import BaseModel


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
