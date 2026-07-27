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
class OcrWordResult:
    """One recognized word, with its own calibrated confidence and geometry.

    Retained through the OCR pipeline so client extractors and the LLM prompt
    can score candidates by OCR reliability, not just regex/keyword fit.
    `digit_corrected` is set when `_normalize_ocr_amounts` substituted a
    confusable character in this word — independent of Tesseract's own
    confidence for that character.
    """

    text: str
    confidence: float
    digit_corrected: bool = False
    left_ratio: float = 0.0
    width_ratio: float = 0.0


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
    # Line bounding box as fractions of this image's width/height — min-left,
    # min-top, and span width aggregated from per-word boxes in
    # image_to_data(). Same receipt-relative convention as height_ratio.
    left_ratio: float = 0.0
    top_ratio: float = 0.0
    width_ratio: float = 0.0
    # This line's own calibrated confidence (same 0..1 sigmoid calibration as
    # the request-level mean) — lets the LLM cleanup prompt (see
    # receipt_understanding.py) leave already-confident lines untouched and
    # concentrate correction effort on low-confidence ones. Also surfaced on
    # the client-facing OcrLine so heuristic extractors can score by OCR
    # reliability. Calibrate(mean(raw)), never mean(calibrate(raw)).
    confidence: float = 1.0
    # Per-word detail for this line. Tuple (not list) so this frozen dataclass
    # stays hashable. Always populated internally; the public API selectively
    # omits words for high-confidence lines (see models.py enrichment gate).
    words: tuple[OcrWordResult, ...] = ()


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
    """Fix OCR letter/digit confusions in RM currency amount positions.

    Kept as a string-in/string-out helper for callers that only need the
    corrected text. Prefer [_normalize_ocr_amount_words] when word-level
    digit_corrected flags are needed.
    """

    def _fix(m: re.Match) -> str:
        return m.group(1) + m.group(2).translate(_OCR_DIGIT_SUBS)

    normalized = _RM_AMOUNT_RE.sub(_fix, text)
    if normalized != text:
        logger.debug(
            "normalize_ocr_amounts: corrected letter/digit confusion in RM amounts"
        )
    return normalized


def _normalize_ocr_amount_words(
    words: list[OcrWordResult],
) -> tuple[str, tuple[OcrWordResult, ...]]:
    """Join words, apply RM digit-confusion fixes, and flag corrected words.

    Digit substitution is char-for-char (same string length), so char offsets
    into the joined line stay valid after correction. Any word whose span
    overlaps a substituted numeric portion is marked `digit_corrected=True`.
    """
    if not words:
        return "", ()

    parts: list[str] = []
    spans: list[tuple[int, int]] = []
    cursor = 0
    for i, word in enumerate(words):
        if i > 0:
            cursor += 1  # single space from " ".join
        start = cursor
        end = start + len(word.text)
        spans.append((start, end))
        parts.append(word.text)
        cursor = end

    joined = " ".join(parts)
    corrected_flags = [False] * len(words)

    def _fix(m: re.Match) -> str:
        prefix, numeric = m.group(1), m.group(2)
        fixed_numeric = numeric.translate(_OCR_DIGIT_SUBS)
        if fixed_numeric != numeric:
            # Flag every word overlapping the numeric span (not the "RM" prefix).
            num_start = m.start(2)
            num_end = m.end(2)
            for wi, (ws, we) in enumerate(spans):
                if ws < num_end and we > num_start:
                    corrected_flags[wi] = True
        return prefix + fixed_numeric

    normalized = _RM_AMOUNT_RE.sub(_fix, joined)
    if normalized != joined:
        logger.debug(
            "normalize_ocr_amounts: corrected letter/digit confusion in RM amounts"
        )

    # Rebuild word texts from the normalized joined string via the same
    # offsets (length-preserving substitution keeps spans valid).
    out_words: list[OcrWordResult] = []
    for i, word in enumerate(words):
        ws, we = spans[i]
        new_text = normalized[ws:we]
        out_words.append(
            OcrWordResult(
                text=new_text,
                confidence=word.confidence,
                digit_corrected=corrected_flags[i],
                left_ratio=word.left_ratio,
                width_ratio=word.width_ratio,
            )
        )
    return normalized, tuple(out_words)


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


def _config(*, psm: str | None = None) -> str:
    # PSM 6 ("single uniform block") keeps a receipt's name/price columns on
    # one text line. PSM 4 ("single column, variable sizes") sounds like the
    # receipt mode but measured worse on typical single-column Malaysian
    # receipts: it splits the price column into separate blocks, orphaning
    # prices from their item names. Adaptive mode may still try PSM 4 for
    # explicitly multi-column layouts (unproven — validate in shadow mode
    # before default-on; see receipt_classifier.py).
    # When [psm] is None, fall back to TESSERACT_PSM env (default "6") — the
    # non-adaptive / legacy path.
    resolved = psm if psm is not None else os.environ.get("TESSERACT_PSM", "6")
    # TESSERACT_LANG defaults to eng+msa (Malay) which ships in the Docker
    # image. Windows dev without msa.traineddata must set TESSERACT_LANG=eng.
    lang = os.environ.get("TESSERACT_LANG", "eng+msa")
    return f"--oem 3 --psm {resolved} -l {lang} -c preserve_interword_spaces=1"


def _adaptive_ocr_enabled() -> bool:
    return os.environ.get("ADAPTIVE_OCR_ENABLED", "0") == "1"


def _adaptive_ocr_shadow() -> bool:
    # Shadow logs classifier/scorer decisions alongside the legacy path without
    # changing what is returned. Ignored when adaptive mode is already on.
    return os.environ.get("ADAPTIVE_OCR_SHADOW", "0") == "1"


def _budget_mode() -> str:
    mode = os.environ.get("OCR_BUDGET_MODE", "interactive").strip().lower()
    if mode not in ("interactive", "batch"):
        logger.warning("invalid OCR_BUDGET_MODE=%r — using interactive", mode)
        return "interactive"
    return mode


def _batch_max_passes() -> int:
    raw = os.environ.get("ADAPTIVE_OCR_BATCH_MAX_PASSES", "4")
    try:
        value = int(raw)
    except ValueError:
        logger.warning("invalid ADAPTIVE_OCR_BATCH_MAX_PASSES=%r — using 4", raw)
        return 4
    return max(2, min(value, 8))


def _boundary_ambiguous_threshold() -> float:
    raw = os.environ.get("ADAPTIVE_OCR_BOUNDARY_AMBIGUOUS", "0.5")
    try:
        return float(raw)
    except ValueError:
        logger.warning("invalid ADAPTIVE_OCR_BOUNDARY_AMBIGUOUS=%r — using 0.5", raw)
        return 0.5


def _token_level_confidence_enabled() -> bool:
    """Opt-in: populate line confidence + selective words on the public API."""
    return os.environ.get("TOKEN_LEVEL_CONFIDENCE", "0") == "1"


# Provisional default — matches the client's lowOcrConfidenceThreshold order
# of magnitude; tune via batch evaluation before treating as final.
_DEFAULT_WORD_ENRICHMENT_THRESHOLD = 0.7


def word_enrichment_threshold() -> float:
    raw = os.environ.get("OCR_WORD_ENRICHMENT_THRESHOLD", "")
    try:
        return float(raw) if raw else _DEFAULT_WORD_ENRICHMENT_THRESHOLD
    except ValueError:
        logger.warning(
            "invalid OCR_WORD_ENRICHMENT_THRESHOLD=%r — using %.1f",
            raw,
            _DEFAULT_WORD_ENRICHMENT_THRESHOLD,
        )
        return _DEFAULT_WORD_ENRICHMENT_THRESHOLD


@dataclass(frozen=True)
class OcrDetailedResult:
    """OCR output plus optional adaptive-strategy telemetry."""

    lines: list[OcrLineResult]
    confidence: float
    strategy_psm: str | None = None
    strategy_bucket: str | None = None
    pass_count: int | None = None
    composite_score: float | None = None


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
    image: np.ndarray, *, label: str, psm: str | None = None
) -> tuple[list[OcrLineResult], float]:
    start = time.perf_counter()
    data = pytesseract.image_to_data(
        image, output_type=Output.DICT, config=_config(psm=psm)
    )
    elapsed = time.perf_counter() - start

    # Group words into lines keyed by Tesseract's block/paragraph/line ids.
    # image_to_data returns rows in reading order, so insertion order of the
    # dict preserves line order. Word bbox heights are tracked alongside so
    # each line's visual prominence (relative to the image) can be derived.
    # Per-word (text, raw_conf, left, width) is retained in `word_records` so
    # digit-correction flagging and client extractors can use token-level
    # confidence — calibrated independently of the (unchanged) line-mean.
    lines: dict[tuple[int, int, int], list[str]] = {}
    heights: dict[tuple[int, int, int], list[int]] = {}
    lefts: dict[tuple[int, int, int], list[int]] = {}
    tops: dict[tuple[int, int, int], list[int]] = {}
    rights: dict[tuple[int, int, int], list[int]] = {}
    line_confidences: dict[tuple[int, int, int], list[float]] = {}
    word_records: dict[tuple[int, int, int], list[tuple[str, float, int, int]]] = {}
    confidences: list[float] = []
    for i, word in enumerate(data["text"]):
        if not word.strip():
            continue
        key = (data["block_num"][i], data["par_num"][i], data["line_num"][i])
        lines.setdefault(key, []).append(word)
        word_left = int(data["left"][i])
        word_top = int(data["top"][i])
        word_width = int(data["width"][i])
        heights.setdefault(key, []).append(int(data["height"][i]))
        lefts.setdefault(key, []).append(word_left)
        tops.setdefault(key, []).append(word_top)
        rights.setdefault(key, []).append(word_left + word_width)
        # conf is 0-100 per word; -1 marks structural (non-word) rows, and 0
        # is Tesseract's "no confidence" marker — both are excluded from the
        # line/request mean. Word-level retention still keeps the raw value
        # (including 0) so extractors can see "unknown" tokens; -1 never
        # reaches here because structural rows have empty text.
        conf = float(data["conf"][i])
        word_records.setdefault(key, []).append((word, conf, word_left, word_width))
        if conf > 0:
            confidences.append(conf)
            line_confidences.setdefault(key, []).append(conf)

    if not lines:
        logger.info(
            "tesseract[%s]: 0 words recognized in %.2fs (blank/unreadable pass)",
            label,
            elapsed,
        )
        return [], 0.0

    image_height = image.shape[0]
    image_width = image.shape[1]
    line_results: list[OcrLineResult] = []
    for key, words in lines.items():
        # Calibrate each word independently via the same sigmoid — never reuse
        # the line-mean calibration (calibrate(mean) ≠ mean(calibrate)).
        raw_word_results = [
            OcrWordResult(
                text=text,
                confidence=(
                    _calibrate_confidence(raw_conf / 100.0) if raw_conf > 0 else 0.0
                ),
                left_ratio=(word_left / image_width if image_width else 0.0),
                width_ratio=(word_width / image_width if image_width else 0.0),
            )
            for text, raw_conf, word_left, word_width in word_records[key]
        ]
        line_text, calibrated_words = _normalize_ocr_amount_words(raw_word_results)
        line_results.append(
            OcrLineResult(
                text=line_text,
                height_ratio=(
                    statistics.median(heights[key]) / image_height
                    if image_height
                    else 0.0
                ),
                left_ratio=(
                    min(lefts[key]) / image_width
                    if image_width and lefts.get(key)
                    else 0.0
                ),
                top_ratio=(
                    min(tops[key]) / image_height
                    if image_height and tops.get(key)
                    else 0.0
                ),
                width_ratio=(
                    (max(rights[key]) - min(lefts[key])) / image_width
                    if image_width and lefts.get(key) and rights.get(key)
                    else 0.0
                ),
                # Same calibration as the request-level mean, applied per line —
                # a line with no positive-confidence words (rare; structural rows
                # are already excluded above) falls back to 0.0, the same
                # "unknown/low" signal a wholly unreadable line should carry.
                # UNCHANGED math: calibrate(mean(raw)), not mean(calibrate(raw)).
                confidence=(
                    _calibrate_confidence(
                        sum(line_confidences[key]) / len(line_confidences[key]) / 100.0
                    )
                    if line_confidences.get(key)
                    else 0.0
                ),
                words=calibrated_words,
            )
        )
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


def _resolve_image_variant(image: np.ndarray, variant: str) -> np.ndarray:
    if variant == "binarized":
        from ocr_api.preprocessing import shadow_binarize

        return shadow_binarize(image)
    return image


def _legacy_run_ocr_detailed(image: np.ndarray) -> OcrDetailedResult:
    """Original fixed-PSM6 + confidence-only binarize-retry path."""
    if os.environ.get("PREPROCESS_ADAPTIVE_BINARIZE"):
        from ocr_api.preprocessing import shadow_binarize

        logger.info("adaptive binarize forced on (PREPROCESS_ADAPTIVE_BINARIZE set)")
        lines, confidence = _run_tesseract(
            shadow_binarize(image), label="forced-binarize"
        )
        return OcrDetailedResult(lines=lines, confidence=confidence)

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
            return OcrDetailedResult(lines=lines, confidence=confidence)

        from ocr_api.preprocessing import shadow_binarize

        logger.info(
            "plain pass confidence %.0f%% is below the %.0f%% retry threshold "
            "(often uneven lighting/shadows) — retrying with adaptive binarization",
            confidence * 100,
            _LOW_CONFIDENCE_RETRY_THRESHOLD * 100,
        )
        binarized = shadow_binarize(image)
        from ocr_api.preprocessing import _dump_debug_image

        _dump_debug_image("thresholded", binarized)
        retry_lines, retry_confidence = _run_tesseract(
            binarized, label="binarize-retry"
        )
        if retry_confidence > confidence:
            logger.info(
                "binarize retry helped: %.0f%% -> %.0f%% — using retry result",
                confidence * 100,
                retry_confidence * 100,
            )
            return OcrDetailedResult(lines=retry_lines, confidence=retry_confidence)
        logger.info(
            "binarize retry didn't help (%.0f%% vs %.0f%% plain) — keeping plain pass",
            retry_confidence * 100,
            confidence * 100,
        )
        return OcrDetailedResult(lines=lines, confidence=confidence)

    return OcrDetailedResult(lines=lines, confidence=confidence)


def _log_shadow_comparison(image: np.ndarray, legacy: OcrDetailedResult) -> None:
    """Classify + score alongside the legacy result; log only, never change output."""
    try:
        from ocr_api.ocr_scoring import score_ocr_pass
        from ocr_api.receipt_classifier import classify_receipt_image

        strategy = classify_receipt_image(image)
        breakdown = score_ocr_pass(
            legacy.lines,
            legacy.confidence,
            image_height=image.shape[0] if image is not None else None,
        )
        logger.info(
            "adaptive_shadow: would_use bucket=%s psm=%s boundary=%.2f "
            "legacy_confidence=%.0f%% composite=%.3f (legacy path still returned)",
            strategy.bucket,
            strategy.psm,
            strategy.boundary_confidence,
            legacy.confidence * 100,
            breakdown.total,
        )
    except Exception:
        logger.exception("adaptive_shadow: comparison failed — ignored")


def _adaptive_run_ocr_detailed(image: np.ndarray) -> OcrDetailedResult:
    """Classification-informed PSM/variant selection with composite-score keep."""
    from ocr_api.ocr_scoring import good_enough_threshold, score_ocr_pass
    from ocr_api.receipt_classifier import classify_receipt_image

    if os.environ.get("PREPROCESS_ADAPTIVE_BINARIZE"):
        from ocr_api.preprocessing import shadow_binarize

        logger.info("adaptive binarize forced on (PREPROCESS_ADAPTIVE_BINARIZE set)")
        lines, confidence = _run_tesseract(
            shadow_binarize(image), label="forced-binarize"
        )
        return OcrDetailedResult(lines=lines, confidence=confidence, pass_count=1)

    strategy = classify_receipt_image(image)
    if strategy.skip_tesseract:
        logger.info(
            "adaptive: near-blank/non-text — skipping Tesseract "
            "(density/regions below floor)"
        )
        return OcrDetailedResult(
            lines=[],
            confidence=0.0,
            strategy_psm=strategy.psm,
            strategy_bucket=strategy.bucket,
            pass_count=0,
            composite_score=0.0,
        )

    budget_mode = _budget_mode()
    max_passes = _batch_max_passes() if budget_mode == "batch" else 2
    ambiguous_cut = _boundary_ambiguous_threshold()
    good_enough = good_enough_threshold()
    image_height = int(image.shape[0]) if image is not None else None

    tried: set[tuple[str, str]] = set()
    best_lines: list[OcrLineResult] = []
    best_confidence = 0.0
    best_score = -1.0
    pass_count = 0

    def _run_candidate(psm: str, variant: str, label: str) -> None:
        nonlocal best_lines, best_confidence, best_score, pass_count
        key = (psm, variant)
        if key in tried:
            return
        tried.add(key)
        candidate_image = _resolve_image_variant(image, variant)
        if variant == "binarized":
            from ocr_api.preprocessing import _dump_debug_image

            _dump_debug_image("thresholded", candidate_image)
        lines, confidence = _run_tesseract(candidate_image, label=label, psm=psm)
        pass_count += 1
        breakdown = score_ocr_pass(lines, confidence, image_height=image_height)
        logger.info(
            "adaptive pass %d: psm=%s variant=%s confidence=%.0f%% "
            "composite=%.3f (amount=%.2f keywords=%.2f coherence=%.2f)",
            pass_count,
            psm,
            variant,
            confidence * 100,
            breakdown.total,
            breakdown.amount,
            breakdown.keywords,
            breakdown.coherence,
        )
        if breakdown.total > best_score:
            best_lines = lines
            best_confidence = confidence
            best_score = breakdown.total

    # Pass 1: classifier-selected strategy.
    plain_start = time.perf_counter()
    _run_candidate(strategy.psm, strategy.image_variant, label="adaptive-pass1")
    plain_elapsed = time.perf_counter() - plain_start

    if best_score >= good_enough:
        logger.info(
            "adaptive: pass 1 composite %.3f >= %.3f good-enough — skipping retry",
            best_score,
            good_enough,
        )
        return OcrDetailedResult(
            lines=best_lines,
            confidence=best_confidence,
            strategy_psm=strategy.psm,
            strategy_bucket=strategy.bucket,
            pass_count=pass_count,
            composite_score=best_score if best_score >= 0 else None,
        )

    if budget_mode == "interactive" and plain_elapsed >= _RETRY_TIME_BUDGET_SECONDS:
        logger.info(
            "adaptive: pass 1 composite %.3f below good-enough but took %.2fs "
            "(>= %.0fs budget) — skipping further passes",
            best_score,
            plain_elapsed,
            _RETRY_TIME_BUDGET_SECONDS,
        )
        return OcrDetailedResult(
            lines=best_lines,
            confidence=best_confidence,
            strategy_psm=strategy.psm,
            strategy_bucket=strategy.bucket,
            pass_count=pass_count,
            composite_score=best_score if best_score >= 0 else None,
        )

    # Pass 2: boundary-confidence chooses alternate-PSM vs binarize.
    if strategy.boundary_confidence < ambiguous_cut:
        logger.info(
            "adaptive: low boundary confidence %.2f — retrying alternate PSM %s",
            strategy.boundary_confidence,
            strategy.alternate_psm,
        )
        _run_candidate(
            strategy.alternate_psm,
            strategy.image_variant,
            label="adaptive-alt-psm",
        )
    else:
        logger.info(
            "adaptive: high boundary confidence %.2f — retrying binarized image "
            "at PSM %s",
            strategy.boundary_confidence,
            strategy.psm,
        )
        _run_candidate(strategy.psm, "binarized", label="adaptive-binarize")

    # Batch mode: try additional unused (psm, variant) pairs from the candidate
    # space until max_passes or good-enough.
    if budget_mode == "batch" and pass_count < max_passes and best_score < good_enough:
        candidates = [
            ("6", "standard"),
            ("4", "standard"),
            ("11", "standard"),
            ("6", "binarized"),
            ("4", "binarized"),
            ("11", "binarized"),
        ]
        for psm, variant in candidates:
            if pass_count >= max_passes or best_score >= good_enough:
                break
            if (psm, variant) in tried:
                continue
            _run_candidate(psm, variant, label=f"adaptive-batch-{psm}-{variant}")

    return OcrDetailedResult(
        lines=best_lines,
        confidence=best_confidence,
        strategy_psm=strategy.psm,
        strategy_bucket=strategy.bucket,
        pass_count=pass_count,
        composite_score=best_score if best_score >= 0 else None,
    )


def run_ocr_detailed(image: np.ndarray) -> OcrDetailedResult:
    """Runs OCR on a preprocessed image.

    Each line carries its own [OcrLineResult.height_ratio] — the Dart
    merchant extractor uses this to prefer a visually large header/logo line
    over the small, uniform itemized body, even without a keyword match.
    Confidence is the calibrated mean word confidence normalized to 0..1
    (sigmoid-squashed to de-inflate Tesseract's high-skew raw scores).

    When ADAPTIVE_OCR_ENABLED=1, selects PSM/image-variant via the heuristic
    classifier and keeps the higher composite-scoring pass. Otherwise uses the
    legacy fixed-PSM6 + confidence-only binarize-retry path. Optional
    ADAPTIVE_OCR_SHADOW=1 logs what adaptive would have done without changing
    the returned result.
    """
    if _adaptive_ocr_enabled():
        return _adaptive_run_ocr_detailed(image)

    result = _legacy_run_ocr_detailed(image)
    if _adaptive_ocr_shadow():
        _log_shadow_comparison(image, result)
    return result


def run_ocr(image: np.ndarray) -> tuple[str, float]:
    """Back-compat wrapper over [run_ocr_detailed]: joins lines the same way
    the old single-pass implementation did. Prefer [run_ocr_detailed] for
    anything that can use per-line height data."""
    result = run_ocr_detailed(image)
    return "\n".join(line.text for line in result.lines), result.confidence
