import logging
import math
import os

import numpy as np
import pytesseract
from pytesseract import Output

logger = logging.getLogger("ocr_api.ocr_engine")

# Windows dev installs typically live outside PATH (e.g. the UB Mannheim
# build at C:\Program Files\Tesseract-OCR\tesseract.exe).
_tesseract_cmd = os.environ.get("TESSERACT_CMD")
if _tesseract_cmd:
    pytesseract.pytesseract.tesseract_cmd = _tesseract_cmd

_CALIB_MIDPOINT = 0.75
_CALIB_STEEPNESS = 8.0


def _calibrate_confidence(raw: float) -> float:
    """De-inflate Tesseract's high-skew word confidences via sigmoid.

    Tesseract reports 85-95 on mediocre scans because its LM fills in probable
    chars. Sigmoid with midpoint 0.75 maps: 0.95→0.91, 0.85→0.73, 0.65→0.27.
    Constants are module-level so they can be tuned after batch runs.
    """
    return 1.0 / (1.0 + math.exp(-_CALIB_STEEPNESS * (raw - _CALIB_MIDPOINT)))


def _config() -> str:
    # PSM 6 ("single uniform block") keeps a receipt's name/price columns on
    # one text line. PSM 4 ("single column, variable sizes") sounds like the
    # receipt mode but measured worse: it splits the price column into
    # separate blocks, orphaning prices from their item names.
    psm = os.environ.get("TESSERACT_PSM", "6")
    # TESSERACT_LANG defaults to eng+msa (Malay) which ships in the Docker
    # image. Windows dev without msa.traineddata must set TESSERACT_LANG=eng.
    lang = os.environ.get("TESSERACT_LANG", "eng+msa")
    return f"--oem 3 --psm {psm} -l {lang} -c preserve_interword_spaces=1"


# Below this calibrated confidence, a second Tesseract pass is attempted with
# adaptive binarization applied (see run_ocr) since low confidence is often a
# sign of uneven lighting a plain pass can't recover from. Handheld receipt
# photos with cluttered backgrounds (e.g. held in hand, busy scene) commonly
# score well under this on the first pass.
_LOW_CONFIDENCE_RETRY_THRESHOLD = 0.4


def _run_tesseract(image: np.ndarray, *, label: str) -> tuple[str, float]:
    data = pytesseract.image_to_data(
        image, output_type=Output.DICT, config=_config()
    )

    # Group words into lines keyed by Tesseract's block/paragraph/line ids.
    # image_to_data returns rows in reading order, so insertion order of the
    # dict preserves line order.
    lines: dict[tuple[int, int, int], list[str]] = {}
    confidences: list[float] = []
    for i, word in enumerate(data["text"]):
        if not word.strip():
            continue
        key = (data["block_num"][i], data["par_num"][i], data["line_num"][i])
        lines.setdefault(key, []).append(word)
        # conf is 0-100 per word; -1 marks structural (non-word) rows, and 0
        # is Tesseract's "no confidence" marker — both are excluded from the mean.
        conf = float(data["conf"][i])
        if conf > 0:
            confidences.append(conf)

    if not lines:
        logger.info("tesseract[%s]: 0 words recognized, confidence=0.0", label)
        return "", 0.0

    joined_text = "\n".join(" ".join(words) for words in lines.values())
    raw_mean = sum(confidences) / len(confidences) / 100.0
    mean_confidence = _calibrate_confidence(raw_mean)
    logger.info(
        "tesseract[%s]: %d words, %d lines, raw_conf=%.3f calibrated_conf=%.3f",
        label,
        len(confidences),
        len(lines),
        raw_mean,
        mean_confidence,
    )
    logger.debug("tesseract[%s] text:\n%s", label, joined_text)
    return joined_text, mean_confidence


def run_ocr(image: np.ndarray) -> tuple[str, float]:
    """Runs OCR on a preprocessed image. Returns (text, mean_confidence).

    Text is rebuilt line-by-line from Tesseract's word-level output — the
    downstream Dart parsers are all line-oriented, so line structure must
    survive. Confidence is the calibrated mean word confidence normalized to
    0..1 (sigmoid-squashed to de-inflate Tesseract's high-skew raw scores).
    """
    # PREPROCESS_ADAPTIVE_BINARIZE forces binarization on every request
    # (useful for manual testing). Otherwise, binarize only appears as an
    # automatic retry below when the plain pass scores low.
    if os.environ.get("PREPROCESS_ADAPTIVE_BINARIZE"):
        from app.preprocessing import shadow_binarize  # lazy import avoids cycle

        logger.info("adaptive binarize forced on (PREPROCESS_ADAPTIVE_BINARIZE set)")
        return _run_tesseract(shadow_binarize(image), label="forced-binarize")

    text, confidence = _run_tesseract(image, label="plain")
    if confidence < _LOW_CONFIDENCE_RETRY_THRESHOLD:
        from app.preprocessing import shadow_binarize  # lazy import avoids cycle

        logger.info(
            "confidence %.3f below retry threshold %.3f, retrying with adaptive binarize",
            confidence,
            _LOW_CONFIDENCE_RETRY_THRESHOLD,
        )
        retry_text, retry_confidence = _run_tesseract(
            shadow_binarize(image), label="binarize-retry"
        )
        if retry_confidence > confidence:
            logger.info(
                "binarize retry improved confidence %.3f -> %.3f, using retry result",
                confidence,
                retry_confidence,
            )
            return retry_text, retry_confidence
        logger.info(
            "binarize retry did not improve confidence (%.3f vs %.3f), keeping plain pass",
            retry_confidence,
            confidence,
        )

    return text, confidence
