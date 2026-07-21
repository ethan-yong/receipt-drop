import logging
import math
import os
import re
import statistics
import time
from dataclasses import dataclass

import numpy as np
import pytesseract
from pytesseract import Output

logger = logging.getLogger("ocr_api.ocr_engine")


@dataclass(frozen=True)
class OcrLineResult:
    """One recognized line, with its visual prominence relative to the rest
    of this same image — used by the Dart merchant extractor to prefer a
    large-font header/logo line over the (usually uniform, small-font)
    itemized body, even when it doesn't match any known keyword."""

    text: str
    # Median word bounding-box height in this line, divided by the image's
    # total height. Relative-to-this-receipt, not an absolute pixel
    # threshold, so it's comparable regardless of a given scan's resolution.
    height_ratio: float


# Common OCR letter/digit confusions in thermal-receipt fonts.
# Z→2 is by far the most frequent on Malaysian receipts (thermal dot-matrix
# fonts render 2 with a flat top that Tesseract reads as Z).
_OCR_DIGIT_SUBS = str.maketrans("ZzOlI", "22011")

# Matches 'RM' followed by 0-3 optional spaces and then a decimal-number-like
# string (may contain the above confused letters instead of digits).
# Substitution is applied only within the numeric portion, leaving all other
# text (merchant names, labels, etc.) untouched.
_RM_AMOUNT_RE = re.compile(r"(RM\s{0,3})([0-9ZzOlI]+(?:\.[0-9ZzOlI]{1,2})?)")


def _normalize_ocr_amounts(text: str) -> str:
    """Fix OCR letter/digit confusions in RM currency amount positions."""

    def _fix(m: re.Match) -> str:
        return m.group(1) + m.group(2).translate(_OCR_DIGIT_SUBS)

    normalized = _RM_AMOUNT_RE.sub(_fix, text)
    if normalized != text:
        logger.debug(
            "normalize_ocr_amounts: corrected letter/digit confusion in RM amounts"
        )
    return normalized


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

# If the plain pass alone already took this long, skip the confidence-triggered
# binarize retry rather than unconditionally doubling an already-slow request.
# A production incident saw a 51.04s plain pass (calibrated confidence 9%)
# followed by a 70.22s binarize retry that made confidence *worse* (6%) and
# was discarded anyway — 122.53s total OCR time for zero benefit. Budget
# chosen so plain-pass-already-slow cases skip straight to the LLM step,
# keeping combined OCR+LLM time under the ~90s ocr-proxy/Cloudflare-tunnel
# ceiling with room to spare. Tune via scripts/process_receipts.ps1 against
# the fixture set before changing.
_RETRY_TIME_BUDGET_SECONDS = 20.0


def _run_tesseract(
    image: np.ndarray, *, label: str
) -> tuple[list[OcrLineResult], float]:
    start = time.perf_counter()
    data = pytesseract.image_to_data(image, output_type=Output.DICT, config=_config())
    elapsed = time.perf_counter() - start

    # Group words into lines keyed by Tesseract's block/paragraph/line ids.
    # image_to_data returns rows in reading order, so insertion order of the
    # dict preserves line order. Word bbox heights are tracked alongside so
    # each line's visual prominence (relative to the image) can be derived.
    lines: dict[tuple[int, int, int], list[str]] = {}
    heights: dict[tuple[int, int, int], list[int]] = {}
    confidences: list[float] = []
    for i, word in enumerate(data["text"]):
        if not word.strip():
            continue
        key = (data["block_num"][i], data["par_num"][i], data["line_num"][i])
        lines.setdefault(key, []).append(word)
        heights.setdefault(key, []).append(int(data["height"][i]))
        # conf is 0-100 per word; -1 marks structural (non-word) rows, and 0
        # is Tesseract's "no confidence" marker — both are excluded from the mean.
        conf = float(data["conf"][i])
        if conf > 0:
            confidences.append(conf)

    if not lines:
        logger.info(
            "tesseract[%s]: 0 words recognized in %.2fs (blank/unreadable pass)",
            label,
            elapsed,
        )
        return [], 0.0

    image_height = image.shape[0]
    line_results = [
        OcrLineResult(
            text=_normalize_ocr_amounts(" ".join(words)),
            height_ratio=(
                statistics.median(heights[key]) / image_height if image_height else 0.0
            ),
        )
        for key, words in lines.items()
    ]
    raw_mean = sum(confidences) / len(confidences) / 100.0
    mean_confidence = _calibrate_confidence(raw_mean)
    logger.info(
        "tesseract[%s]: finished in %.2fs — %d words across %d lines, "
        "confidence %.0f%% raw / %.0f%% calibrated",
        label,
        elapsed,
        len(confidences),
        len(lines),
        raw_mean * 100,
        mean_confidence * 100,
    )
    logger.debug(
        "tesseract[%s] text:\n%s",
        label,
        "\n".join(line.text for line in line_results),
    )
    return line_results, mean_confidence


def run_ocr_detailed(image: np.ndarray) -> tuple[list[OcrLineResult], float]:
    """Runs OCR on a preprocessed image. Returns (lines, mean_confidence).

    Each line carries its own [OcrLineResult.height_ratio] — the Dart
    merchant extractor uses this to prefer a visually large header/logo line
    over the small, uniform itemized body, even without a keyword match.
    Confidence is the calibrated mean word confidence normalized to 0..1
    (sigmoid-squashed to de-inflate Tesseract's high-skew raw scores).
    """
    # PREPROCESS_ADAPTIVE_BINARIZE forces binarization on every request
    # (useful for manual testing). Otherwise, binarize only appears as an
    # automatic retry below when the plain pass scores low.
    if os.environ.get("PREPROCESS_ADAPTIVE_BINARIZE"):
        from ocr_api.preprocessing import shadow_binarize  # lazy import avoids cycle

        logger.info("adaptive binarize forced on (PREPROCESS_ADAPTIVE_BINARIZE set)")
        return _run_tesseract(shadow_binarize(image), label="forced-binarize")

    plain_start = time.perf_counter()
    lines, confidence = _run_tesseract(image, label="plain")
    plain_elapsed = time.perf_counter() - plain_start

    if confidence < _LOW_CONFIDENCE_RETRY_THRESHOLD:
        if plain_elapsed >= _RETRY_TIME_BUDGET_SECONDS:
            logger.info(
                "plain pass confidence %.0f%% is below the %.0f%% retry threshold "
                "but took %.2fs (>= %.0fs budget) — skipping binarize retry to "
                "protect the request's overall latency budget",
                confidence * 100,
                _LOW_CONFIDENCE_RETRY_THRESHOLD * 100,
                plain_elapsed,
                _RETRY_TIME_BUDGET_SECONDS,
            )
            return lines, confidence

        from ocr_api.preprocessing import shadow_binarize  # lazy import avoids cycle

        logger.info(
            "plain pass confidence %.0f%% is below the %.0f%% retry threshold "
            "(often uneven lighting/shadows) — retrying with adaptive binarization",
            confidence * 100,
            _LOW_CONFIDENCE_RETRY_THRESHOLD * 100,
        )
        retry_lines, retry_confidence = _run_tesseract(
            shadow_binarize(image), label="binarize-retry"
        )
        if retry_confidence > confidence:
            logger.info(
                "binarize retry helped: %.0f%% -> %.0f%% — using retry result",
                confidence * 100,
                retry_confidence * 100,
            )
            return retry_lines, retry_confidence
        logger.info(
            "binarize retry didn't help (%.0f%% vs %.0f%% plain) — keeping plain pass",
            retry_confidence * 100,
            confidence * 100,
        )

    return lines, confidence


def run_ocr(image: np.ndarray) -> tuple[str, float]:
    """Back-compat wrapper over [run_ocr_detailed]: joins lines the same way
    the old single-pass implementation did. Prefer [run_ocr_detailed] for
    anything that can use per-line height data."""
    lines, confidence = run_ocr_detailed(image)
    return "\n".join(line.text for line in lines), confidence
