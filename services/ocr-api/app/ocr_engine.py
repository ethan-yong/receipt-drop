import numpy as np
from paddleocr import PaddleOCR

_engine: PaddleOCR | None = None


def get_engine() -> PaddleOCR:
    """Lazy singleton — loading PaddleOCR's model weights is expensive, so a
    container instance should only pay that cost once, not per request."""
    global _engine
    if _engine is None:
        _engine = PaddleOCR(use_angle_cls=True, lang="en", show_log=False)
    return _engine


def run_ocr(image: np.ndarray) -> tuple[str, float]:
    """Runs OCR on a preprocessed image. Returns (text, mean_confidence)."""
    result = get_engine().ocr(image, cls=True)
    lines = result[0] if result else None
    if not lines:
        return "", 0.0

    texts: list[str] = []
    confidences: list[float] = []
    for _box, (text, confidence) in lines:
        texts.append(text)
        confidences.append(confidence)

    joined_text = "\n".join(texts)
    mean_confidence = sum(confidences) / len(confidences) if confidences else 0.0
    return joined_text, mean_confidence
