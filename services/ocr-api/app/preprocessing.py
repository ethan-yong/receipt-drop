import os

import cv2
import numpy as np

# Receipts are rarely rotated more than this in practice; clamping avoids
# over-rotating near-square/noisy inputs where the minAreaRect angle is unstable.
_MAX_DESKEW_ANGLE_DEG = 15.0

# Upscale images narrower than this so Tesseract sees ~300 DPI equivalent.
# Overridable via MIN_OCR_WIDTH env var.
_MIN_OCR_WIDTH = int(os.environ.get("MIN_OCR_WIDTH", "1500"))


class InvalidImageError(ValueError):
    """Raised when the input bytes cannot be decoded as an image."""


def decode_image(image_bytes: bytes) -> np.ndarray:
    array = np.frombuffer(image_bytes, dtype=np.uint8)
    image = cv2.imdecode(array, cv2.IMREAD_COLOR)
    if image is None:
        raise InvalidImageError("could not decode image bytes")
    return image


def _skew_angle(gray: np.ndarray) -> float:
    _, thresh = cv2.threshold(
        gray, 0, 255, cv2.THRESH_BINARY_INV | cv2.THRESH_OTSU
    )
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
    if abs(angle) < 0.1 or abs(angle) > _MAX_DESKEW_ANGLE_DEG:
        return image
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
        return image
    scale = min_width / w
    return cv2.resize(image, (min_width, int(h * scale)), interpolation=cv2.INTER_CUBIC)


def enhance_contrast(image: np.ndarray) -> np.ndarray:
    gray = (
        cv2.cvtColor(image, cv2.COLOR_BGR2GRAY) if image.ndim == 3 else image
    )
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    return clahe.apply(gray)


def binarize(gray: np.ndarray) -> np.ndarray:
    _, binary = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY | cv2.THRESH_OTSU)
    return binary


def shadow_binarize(gray: np.ndarray) -> np.ndarray:
    """Adaptive threshold for scans with uneven lighting (e.g. phone-flash shadows).

    Uses a large block size (51) to handle gradients across the receipt.
    Opt-in only — can hurt clean thermal-print receipts. Enable via
    PREPROCESS_ADAPTIVE_BINARIZE=1 (applied in ocr_engine.run_ocr, not here).
    """
    if gray.ndim == 3:
        gray = cv2.cvtColor(gray, cv2.COLOR_BGR2GRAY)
    return cv2.adaptiveThreshold(
        gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 51, 11
    )


def _order_points(pts: np.ndarray) -> np.ndarray:
    """Order 4 points as top-left, top-right, bottom-right, bottom-left."""
    s = pts.sum(axis=1)
    diff = np.diff(pts, axis=1)
    return np.array(
        [
            pts[np.argmin(s)],    # top-left: smallest x+y
            pts[np.argmin(diff)], # top-right: smallest x-y
            pts[np.argmax(s)],    # bottom-right: largest x+y
            pts[np.argmax(diff)], # bottom-left: largest x-y
        ],
        dtype=np.float32,
    )


def perspective_correct(image: np.ndarray) -> np.ndarray:
    """Correct keystoning by detecting the receipt's 4 corners and applying a
    homography (getPerspectiveTransform + warpPerspective).

    Returns the original image unchanged when no clean 4-sided contour is
    found — corner detection is unreliable on cluttered backgrounds (receipt
    on a patterned tablecloth, crumpled paper, etc.). Enable via
    PREPROCESS_PERSPECTIVE=1; off by default.
    """
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY) if image.ndim == 3 else image
    blurred = cv2.GaussianBlur(gray, (5, 5), 0)
    edges = cv2.Canny(blurred, 50, 150)
    contours, _ = cv2.findContours(
        edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
    )
    if not contours:
        return image
    for contour in sorted(contours, key=cv2.contourArea, reverse=True)[:5]:
        peri = cv2.arcLength(contour, True)
        approx = cv2.approxPolyDP(contour, 0.02 * peri, True)
        if len(approx) != 4:
            continue
        pts = approx.reshape(4, 2).astype(np.float32)
        rect = _order_points(pts)
        tl, tr, br, bl = rect
        w = int(max(np.linalg.norm(br - bl), np.linalg.norm(tr - tl)))
        h = int(max(np.linalg.norm(tr - br), np.linalg.norm(tl - bl)))
        if w < 10 or h < 10:
            continue
        dst = np.array(
            [[0, 0], [w - 1, 0], [w - 1, h - 1], [0, h - 1]], dtype=np.float32
        )
        M = cv2.getPerspectiveTransform(rect, dst)
        return cv2.warpPerspective(image, M, (w, h))
    return image


def preprocess(image_bytes: bytes) -> np.ndarray:
    """Decode -> [perspective] -> deskew -> upscale -> grayscale.

    Returns an ndarray ready for Tesseract. Deliberately NO CLAHE or
    pre-binarization by default: Tesseract runs its own Otsu pass internally,
    and measured side-by-side both steps degraded recognition (CLAHE amplifies
    noise into garbage words on clean scans). They were tuned for the previous
    PaddleOCR engine.

    Opt-in flags (env vars):
      PREPROCESS_PERSPECTIVE=1   — homography correction for camera keystoning
      PREPROCESS_ADAPTIVE_BINARIZE=1 — shadow binarization (applied in run_ocr)
      MIN_OCR_WIDTH=N            — override minimum width before upscaling
    """
    image = decode_image(image_bytes)
    if os.environ.get("PREPROCESS_PERSPECTIVE"):
        image = perspective_correct(image)
    rotated = deskew(image)
    upscaled = upscale_for_ocr(rotated)
    return (
        cv2.cvtColor(upscaled, cv2.COLOR_BGR2GRAY)
        if upscaled.ndim == 3
        else upscaled
    )
