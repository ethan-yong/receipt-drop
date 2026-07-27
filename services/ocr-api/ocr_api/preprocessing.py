import logging
import os
import time
from pathlib import Path

import cv2
import numpy as np

logger = logging.getLogger("ocr_api.preprocessing")

# Receipts are rarely rotated more than this in practice; clamping avoids
# over-rotating near-square/noisy inputs where the minAreaRect angle is unstable.
_MAX_DESKEW_ANGLE_DEG = 15.0

# Upscale images narrower than this so Tesseract sees ~300 DPI equivalent.
# Overridable via MIN_OCR_WIDTH env var.
#
# 2500 (not 1500) measured on the 720px handheld rock_cafe fixture: at 1500
# the header read "RESTORAN AME" and item rows dropped; at 2500 (with the
# adaptive-binarize retry) all 9 item lines and "RESTORAN ANWAR MAU." came
# through, calibrated confidence 0.337 -> 0.362. Cost: Tesseract time scales
# ~with pixel area, so narrow images OCR ~2.8x slower than at 1500.
_MIN_OCR_WIDTH = int(os.environ.get("MIN_OCR_WIDTH", "2500"))

# Document-detection confidence gate defaults (read at call time for monkeypatch).
_DEFAULT_MIN_DOCUMENT_AREA_RATIO = 0.2
_DEFAULT_MAX_DOCUMENT_AREA_RATIO = 0.98
# Reject quads whose corners hug the frame border (Canny false positive on noise).
_BORDER_MARGIN_PX = 4.0

# CLAHE fires only when grayscale std-dev is below this threshold. Tune against
# real fixtures via scripts/process_receipts.ps1 before changing.
_CLAHE_CONTRAST_STD_THRESHOLD = float(
    os.environ.get("PREPROCESS_CLAHE_CONTRAST_THRESHOLD", "45.0")
)

# Unsharp-mask defaults — mild, controlled sharpening (opt-in via PREPROCESS_SHARPEN=1).
_SHARPEN_AMOUNT = float(os.environ.get("PREPROCESS_SHARPEN_AMOUNT", "0.6"))
_SHARPEN_SIGMA = float(os.environ.get("PREPROCESS_SHARPEN_SIGMA", "1.0"))

# Adaptive threshold degeneracy band — outside this white-pixel ratio, use OTSU.
_ADAPTIVE_WHITE_RATIO_MIN = 0.02
_ADAPTIVE_WHITE_RATIO_MAX = 0.98

# Illumination normalization — tune against real fixtures via
# scripts/process_receipts.ps1 before changing.
_DEFAULT_ILLUMINATION_UNEVENNESS_THRESHOLD = 25.0
_DEFAULT_ILLUMINATION_KERNEL_SIGMA = 40.0
_DEFAULT_ILLUMINATION_TARGET_BRIGHTNESS = 180.0
_DEFAULT_ILLUMINATION_MIN_MEAN_BRIGHTNESS = 40.0
_ILLUMINATION_GRID_ROWS = 4
_ILLUMINATION_GRID_COLS = 4
# Guard: revert if corrected image has this many more clipped (0/255) pixels.
_ILLUMINATION_CLIP_MARGIN = 0.05
# Guard: revert if Otsu between-class variance drops by more than this fraction.
_ILLUMINATION_BIMODALITY_DROP_RATIO = 0.5

_DEFAULT_DEBUG_DIR = Path(__file__).resolve().parent.parent / ".debug"


class InvalidImageError(ValueError):
    """Raised when the input bytes cannot be decoded as an image."""


def decode_image(image_bytes: bytes) -> np.ndarray:
    array = np.frombuffer(image_bytes, dtype=np.uint8)
    image = cv2.imdecode(array, cv2.IMREAD_COLOR)
    if image is None:
        raise InvalidImageError("could not decode image bytes")
    return image


def _skew_angle(gray: np.ndarray) -> float:
    _, thresh = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY_INV | cv2.THRESH_OTSU)
    coords = cv2.findNonZero(thresh)
    if coords is None:
        return 0.0
    angle = cv2.minAreaRect(coords)[-1]
    # cv2.minAreaRect's angle convention changed across OpenCV versions:
    # older builds return (-90, 0], newer ones (0, 90]. Normalize both to a
    # small rotation around 0 rather than snapping to the nearest 90 degrees
    # (a straight scan legitimately reports 90 in the new convention).
    if angle < -45:
        angle = 90 + angle
    elif angle > 45:
        angle = angle - 90
    return angle


def deskew(image: np.ndarray) -> np.ndarray:
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    angle = _skew_angle(gray)
    # An estimate beyond the plausible tilt range is minAreaRect noise, not a
    # real skew (e.g. it reports 90 for a straight scan whose text block is
    # wider than tall). Rotating by a clamped version of a bogus angle
    # destroys a perfectly good image, so skip instead of clamping.
    if abs(angle) < 0.1:
        logger.info(
            "deskew: already straight (angle=%.2f deg) — no rotation needed", angle
        )
        return image
    if abs(angle) > _MAX_DESKEW_ANGLE_DEG:
        logger.info(
            "deskew: angle=%.2f deg exceeds the %.0f deg plausible tilt range "
            "(likely detector noise, not a real skew) — leaving image as-is",
            angle,
            _MAX_DESKEW_ANGLE_DEG,
        )
        return image
    logger.info("deskew: image is tilted %.2f deg — rotating to straighten it", angle)
    h, w = image.shape[:2]
    center = (w / 2, h / 2)
    matrix = cv2.getRotationMatrix2D(center, angle, 1.0)
    return cv2.warpAffine(
        image,
        matrix,
        (w, h),
        flags=cv2.INTER_CUBIC,
        borderMode=cv2.BORDER_REPLICATE,
    )


def upscale_for_ocr(image: np.ndarray, min_width: int = _MIN_OCR_WIDTH) -> np.ndarray:
    """Scale up images narrower than [min_width] so Tesseract sees adequate DPI.

    Tesseract is calibrated for ~300 DPI. Phone-photo crops of narrow thermal
    receipts can be 200-800px wide (effective 75-300 DPI), degrading word
    confidence measurably. INTER_CUBIC preserves sub-pixel detail during
    upsampling. Images already at or above [min_width] are returned unchanged.
    """
    h, w = image.shape[:2]
    if w >= min_width:
        logger.info(
            "upscale: image is already %dx%d (>= %dpx minimum) — no resize needed",
            w,
            h,
            min_width,
        )
        return image
    scale = min_width / w
    new_h = int(h * scale)
    logger.info(
        "upscale: %dx%d is narrower than the %dpx minimum — scaling up %.2fx to %dx%d",
        w,
        h,
        min_width,
        scale,
        min_width,
        new_h,
    )
    return cv2.resize(image, (min_width, new_h), interpolation=cv2.INTER_CUBIC)


def _is_low_contrast(gray: np.ndarray) -> bool:
    """True when the image's grayscale std-dev suggests CLAHE may help."""
    return float(gray.std()) < _CLAHE_CONTRAST_STD_THRESHOLD


def _illumination_threshold() -> float:
    return float(
        os.environ.get(
            "PREPROCESS_ILLUMINATION_THRESHOLD",
            str(_DEFAULT_ILLUMINATION_UNEVENNESS_THRESHOLD),
        )
    )


def _illumination_kernel_sigma() -> float:
    return float(
        os.environ.get(
            "PREPROCESS_ILLUMINATION_KERNEL_SIGMA",
            str(_DEFAULT_ILLUMINATION_KERNEL_SIGMA),
        )
    )


def _illumination_target_brightness() -> float:
    return float(
        os.environ.get(
            "PREPROCESS_ILLUMINATION_TARGET",
            str(_DEFAULT_ILLUMINATION_TARGET_BRIGHTNESS),
        )
    )


def _illumination_min_mean_brightness() -> float:
    return float(
        os.environ.get(
            "PREPROCESS_ILLUMINATION_MIN_MEAN",
            str(_DEFAULT_ILLUMINATION_MIN_MEAN_BRIGHTNESS),
        )
    )


def illumination_unevenness_score(
    gray: np.ndarray,
    rows: int = _ILLUMINATION_GRID_ROWS,
    cols: int = _ILLUMINATION_GRID_COLS,
) -> float:
    """Max-min spread of coarse grid block means — spatial lighting unevenness."""
    if gray.ndim == 3:
        gray = cv2.cvtColor(gray, cv2.COLOR_BGR2GRAY)
    height, width = gray.shape[:2]
    if height < rows or width < cols:
        return 0.0
    block_means: list[float] = []
    for row in range(rows):
        y0 = row * height // rows
        y1 = (row + 1) * height // rows
        for col in range(cols):
            x0 = col * width // cols
            x1 = (col + 1) * width // cols
            block = gray[y0:y1, x0:x1]
            if block.size > 0:
                block_means.append(float(block.mean()))
    if len(block_means) < 2:
        return 0.0
    return max(block_means) - min(block_means)


def is_unevenly_lit(gray: np.ndarray) -> bool:
    """True when grid unevenness exceeds threshold and image is not globally dark."""
    if gray.ndim == 3:
        gray = cv2.cvtColor(gray, cv2.COLOR_BGR2GRAY)
    mean_brightness = float(gray.mean())
    if mean_brightness < _illumination_min_mean_brightness():
        return False
    return illumination_unevenness_score(gray) > _illumination_threshold()


def _otsu_between_class_variance(gray: np.ndarray) -> float:
    hist = cv2.calcHist([gray], [0], None, [256], [0, 256]).flatten()
    total = float(gray.size)
    sum_total = float(np.dot(np.arange(256), hist))
    sum_b = 0.0
    w_b = 0.0
    max_var = 0.0
    for threshold in range(256):
        w_b += hist[threshold]
        if w_b == 0:
            continue
        w_f = total - w_b
        if w_f == 0:
            break
        sum_b += threshold * hist[threshold]
        mean_b = sum_b / w_b
        mean_f = (sum_total - sum_b) / w_f
        var_between = w_b * w_f * (mean_b - mean_f) ** 2
        if var_between > max_var:
            max_var = var_between
    return float(max_var)


def _clipped_pixel_ratio(gray: np.ndarray) -> float:
    return float(np.mean((gray == 0) | (gray == 255)))


def _illumination_clipping_guard_failed(
    original: np.ndarray, corrected: np.ndarray
) -> bool:
    """True when correction materially increased saturation at 0/255."""
    before = _clipped_pixel_ratio(original)
    after = _clipped_pixel_ratio(corrected)
    return after > before + _ILLUMINATION_CLIP_MARGIN


def _illumination_bimodality_guard_failed(
    original: np.ndarray, corrected: np.ndarray
) -> bool:
    """True when correction washed out text/background histogram separation."""
    before = _otsu_between_class_variance(original)
    after = _otsu_between_class_variance(corrected)
    if before <= 0:
        return False
    return after < before * (1.0 - _ILLUMINATION_BIMODALITY_DROP_RATIO)


def correct_illumination(gray: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Flat-field shading correction via large-kernel background division.

    Returns (corrected grayscale, background estimate as uint8).
    """
    if gray.ndim == 3:
        gray = cv2.cvtColor(gray, cv2.COLOR_BGR2GRAY)
    sigma = _illumination_kernel_sigma()
    background = cv2.GaussianBlur(gray.astype(np.float32), (0, 0), sigma)
    background = np.maximum(background, 1.0)
    target = _illumination_target_brightness()
    corrected = (gray.astype(np.float32) / background) * target
    corrected = np.clip(corrected, 0, 255).astype(np.uint8)
    background_u8 = np.clip(background, 0, 255).astype(np.uint8)
    return corrected, background_u8


def normalize_illumination(gray: np.ndarray) -> np.ndarray:
    """Detect uneven lighting and flatten gradient when guards pass.

    Heuristic-gated on by default (PREPROCESS_ILLUMINATION=0 to disable).
    Never raises — failures skip the stage and return the input unchanged.
    """
    if gray.ndim == 3:
        gray = cv2.cvtColor(gray, cv2.COLOR_BGR2GRAY)
    original = gray

    if os.environ.get("PREPROCESS_ILLUMINATION", "1") == "0":
        logger.info("illumination: disabled via PREPROCESS_ILLUMINATION=0")
        return original

    try:
        score = illumination_unevenness_score(original)
        if not is_unevenly_lit(original):
            logger.info(
                "illumination: even lighting (score=%.1f <= %.1f) — skipping",
                score,
                _illumination_threshold(),
            )
            return original

        corrected, background = correct_illumination(original)
        _dump_debug_image("illumination_background", background)
        _dump_debug_image("illumination_corrected", corrected)

        if _illumination_clipping_guard_failed(original, corrected):
            logger.info(
                "illumination: clipping guard failed — reverting to pre-correction"
            )
            _dump_debug_image("illumination_reverted", original)
            return original

        if _illumination_bimodality_guard_failed(original, corrected):
            logger.info(
                "illumination: bimodality guard failed — reverting to pre-correction"
            )
            _dump_debug_image("illumination_reverted", corrected)
            return original

        logger.info(
            "illumination: applied correction (score=%.1f -> %.1f)",
            score,
            illumination_unevenness_score(corrected),
        )
        _dump_debug_image("illumination", corrected)
        return corrected
    except Exception:
        logger.exception("illumination: stage failed — using pre-stage image")
        return original


def enhance_contrast(image: np.ndarray) -> np.ndarray:
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY) if image.ndim == 3 else image
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    return clahe.apply(gray)


def sharpen(gray: np.ndarray) -> np.ndarray:
    """Mild unsharp mask — opt-in via PREPROCESS_SHARPEN=1."""
    if gray.ndim == 3:
        gray = cv2.cvtColor(gray, cv2.COLOR_BGR2GRAY)
    blurred = cv2.GaussianBlur(gray, (0, 0), _SHARPEN_SIGMA)
    amount = _SHARPEN_AMOUNT
    return cv2.addWeighted(gray, 1.0 + amount, blurred, -amount, 0)


def binarize(gray: np.ndarray) -> np.ndarray:
    _, binary = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY | cv2.THRESH_OTSU)
    return binary


def _adaptive_output_is_degenerate(binary: np.ndarray) -> bool:
    white_ratio = float(np.mean(binary == 255))
    return (
        white_ratio < _ADAPTIVE_WHITE_RATIO_MIN
        or white_ratio > _ADAPTIVE_WHITE_RATIO_MAX
    )


def shadow_binarize(gray: np.ndarray) -> np.ndarray:
    """Adaptive threshold for scans with uneven lighting (e.g. phone-flash shadows).

    Uses a large block size (51) to handle gradients across the receipt.
    Falls back to OTSU when the adaptive output is degenerate (near all-white
    or all-black). Opt-in force via PREPROCESS_ADAPTIVE_BINARIZE=1 in ocr_engine.
    """
    if gray.ndim == 3:
        gray = cv2.cvtColor(gray, cv2.COLOR_BGR2GRAY)
    adaptive = cv2.adaptiveThreshold(
        gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 51, 11
    )
    if _adaptive_output_is_degenerate(adaptive):
        logger.info(
            "shadow_binarize: adaptive output degenerate (white ratio %.3f) — "
            "falling back to OTSU",
            float(np.mean(adaptive == 255)),
        )
        return binarize(gray)
    return adaptive


def _order_points(pts: np.ndarray) -> np.ndarray:
    """Order 4 points as top-left, top-right, bottom-right, bottom-left."""
    s = pts.sum(axis=1)
    diff = np.diff(pts, axis=1)
    return np.array(
        [
            pts[np.argmin(s)],  # top-left: smallest x+y
            pts[np.argmin(diff)],  # top-right: smallest x-y
            pts[np.argmax(s)],  # bottom-right: largest x+y
            pts[np.argmax(diff)],  # bottom-left: largest x-y
        ],
        dtype=np.float32,
    )


def _document_area_bounds() -> tuple[float, float]:
    min_ratio = float(
        os.environ.get("MIN_DOCUMENT_AREA_RATIO", str(_DEFAULT_MIN_DOCUMENT_AREA_RATIO))
    )
    max_ratio = float(
        os.environ.get("MAX_DOCUMENT_AREA_RATIO", str(_DEFAULT_MAX_DOCUMENT_AREA_RATIO))
    )
    return min_ratio, max_ratio


def _quad_is_frame_border(pts: np.ndarray, width: int, height: int) -> bool:
    """True when all corners sit on the image border — not a real document."""
    margin = _BORDER_MARGIN_PX
    xs = pts[:, 0]
    ys = pts[:, 1]
    on_border = (
        (xs <= margin)
        | (xs >= width - 1 - margin)
        | (ys <= margin)
        | (ys >= height - 1 - margin)
    )
    return bool(np.all(on_border))


def detect_document_corners(image: np.ndarray) -> np.ndarray | None:
    """Find a confident 4-corner document quad, or None if none qualifies."""
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY) if image.ndim == 3 else image
    height, width = gray.shape[:2]
    frame_area = float(height * width)
    if frame_area <= 0:
        return None

    min_area_ratio, max_area_ratio = _document_area_bounds()
    blurred = cv2.GaussianBlur(gray, (5, 5), 0)
    edges = cv2.Canny(blurred, 50, 150)
    kernel = np.ones((3, 3), dtype=np.uint8)
    edges = cv2.dilate(edges, kernel, iterations=1)
    contours, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return None

    for contour in sorted(contours, key=cv2.contourArea, reverse=True)[:5]:
        area_ratio = cv2.contourArea(contour) / frame_area
        if area_ratio < min_area_ratio or area_ratio > max_area_ratio:
            continue
        peri = cv2.arcLength(contour, True)
        approx = cv2.approxPolyDP(contour, 0.02 * peri, True)
        if len(approx) != 4:
            continue
        if not cv2.isContourConvex(approx):
            continue
        pts = approx.reshape(4, 2).astype(np.float32)
        rect = _order_points(pts)
        if _quad_is_frame_border(rect, width, height):
            continue
        tl, tr, br, bl = rect
        w = int(max(np.linalg.norm(br - bl), np.linalg.norm(tr - tl)))
        h = int(max(np.linalg.norm(tr - br), np.linalg.norm(tl - bl)))
        if w < 10 or h < 10:
            continue
        return rect
    return None


def perspective_correct(image: np.ndarray) -> np.ndarray:
    """Correct keystoning when a confident document quad is detected.

    Returns the original image unchanged when [detect_document_corners] finds
    nothing reliable. Enable via PREPROCESS_PERSPECTIVE=1; off by default.
    """
    rect = detect_document_corners(image)
    if rect is None:
        logger.info("perspective: skipped (no confident document quad found)")
        return image
    tl, tr, br, bl = rect
    w = int(max(np.linalg.norm(br - bl), np.linalg.norm(tr - tl)))
    h = int(max(np.linalg.norm(tr - br), np.linalg.norm(tl - bl)))
    logger.info("perspective: correcting to %dx%d quad", w, h)
    dst = np.array([[0, 0], [w - 1, 0], [w - 1, h - 1], [0, h - 1]], dtype=np.float32)
    M = cv2.getPerspectiveTransform(rect, dst)
    return cv2.warpPerspective(image, M, (w, h))


def _debug_dir() -> Path:
    return Path(os.environ.get("PREPROCESS_DEBUG_DIR", str(_DEFAULT_DEBUG_DIR)))


def _dump_debug_image(step: str, image: np.ndarray) -> None:
    """Write an intermediate pipeline stage to disk when PREPROCESS_DEBUG is set."""
    if not os.environ.get("PREPROCESS_DEBUG"):
        return
    debug_dir = _debug_dir()
    debug_dir.mkdir(parents=True, exist_ok=True)
    path = debug_dir / f"{time.time_ns()}_{step}.png"
    cv2.imwrite(str(path), image)
    logger.debug("debug dump: wrote %s", path)


def preprocess(image_bytes: bytes) -> np.ndarray:
    """Decode, optional perspective, deskew, upscale, grayscale, illumination,
    CLAHE, sharpen.

    Returns a 2D ndarray ready for Tesseract. CLAHE and illumination are
    heuristic/opt-in gated; pre-binarization is not applied here (Tesseract
    thresholds internally; retry binarization lives in run_ocr_detailed).

    Opt-in flags (env vars):
      PREPROCESS_PERSPECTIVE=1        — homography when a confident quad is found
      PREPROCESS_ILLUMINATION=0       — disable illumination correction (default on)
      PREPROCESS_ILLUMINATION_THRESHOLD — grid unevenness gate (default 25)
      PREPROCESS_ILLUMINATION_KERNEL_SIGMA — background blur sigma (default 40)
      PREPROCESS_ILLUMINATION_TARGET  — post-correction target brightness (180)
      PREPROCESS_ILLUMINATION_MIN_MEAN — skip globally dark images (default 40)
      PREPROCESS_CLAHE=0              — disable contrast-gated CLAHE (default on)
      PREPROCESS_CLAHE_CONTRAST_THRESHOLD — std-dev gate for CLAHE (default 45)
      PREPROCESS_SHARPEN=1            — unsharp mask after grayscale (default off)
      PREPROCESS_SHARPEN_AMOUNT/SIGMA — sharpen tuning knobs
      PREPROCESS_ADAPTIVE_BINARIZE=1   — force binarize pass (in run_ocr_detailed)
      PREPROCESS_DEBUG=1              — dump stage PNGs to PREPROCESS_DEBUG_DIR
      MIN_OCR_WIDTH=N                 — override minimum width before upscaling
    """
    start = time.perf_counter()
    image = decode_image(image_bytes)
    logger.info(
        "preprocess: decoded a %dx%d image from %.1f KB of input",
        image.shape[1],
        image.shape[0],
        len(image_bytes) / 1024,
    )
    _dump_debug_image("original", image)

    if os.environ.get("PREPROCESS_PERSPECTIVE"):
        image = perspective_correct(image)
        _dump_debug_image("perspective", image)

    rotated = deskew(image)
    _dump_debug_image("deskewed", rotated)

    upscaled = upscale_for_ocr(rotated)
    _dump_debug_image("upscaled", upscaled)

    result = (
        cv2.cvtColor(upscaled, cv2.COLOR_BGR2GRAY) if upscaled.ndim == 3 else upscaled
    )
    _dump_debug_image("grayscale", result)

    result = normalize_illumination(result)

    clahe_enabled = os.environ.get("PREPROCESS_CLAHE", "1") != "0"
    if clahe_enabled and _is_low_contrast(result):
        logger.info(
            "preprocess: low contrast (std=%.1f < %.1f) — applying CLAHE",
            result.std(),
            _CLAHE_CONTRAST_STD_THRESHOLD,
        )
        result = enhance_contrast(result)
        _dump_debug_image("clahe", result)

    if os.environ.get("PREPROCESS_SHARPEN"):
        result = sharpen(result)
        _dump_debug_image("sharpened", result)

    logger.info(
        "preprocess: finished in %.2fs — ready for OCR at %dx%d",
        time.perf_counter() - start,
        result.shape[1],
        result.shape[0],
    )
    return result
