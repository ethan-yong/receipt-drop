"""Heuristic pre-OCR layout classifier for adaptive Tesseract strategy selection.

Takes the already-preprocessed grayscale image (post-CLAHE/illumination, pre-
Tesseract — the same ndarray `preprocess()` returns) and maps geometric
features onto a small static strategy bucket. No ML model, no Tesseract
dependency — mirrors the fail-safe heuristic style of
`lib/domain/logic/receipt_layout_analyzer.dart` and the dict-table shape of
`ocr_api/skills/orchestrator.py`.

Fails safe to the default strategy (PSM 6, standard image) on any internal
error so a classifier bug can't take down `/ocr`.
"""

from __future__ import annotations

import logging
import os
from dataclasses import dataclass

import cv2
import numpy as np

logger = logging.getLogger("ocr_api.receipt_classifier")

# Density / region thresholds — provisional defaults pending batch-tool tuning.
_NEAR_BLANK_DENSITY = 0.002
_NEAR_BLANK_REGIONS = 3
_SPARSE_DENSITY = 0.02
_SPARSE_REGIONS = 40
_COLUMN_GAP_MIN_WIDTH_FRACTION = 0.08
_COLUMN_GAP_MAX_DENSITY_FRACTION = 0.15
_BOUNDARY_MARGIN = 0.25  # feature distance-to-threshold fraction → low confidence


def _safe_float_env(name: str, default: float) -> float:
    """Parse a float env var; malformed values fall back to [default]."""
    raw = os.environ.get(name)
    if raw is None or raw.strip() == "":
        return default
    try:
        return float(raw)
    except ValueError:
        logger.warning("invalid %s=%r — using default %.4f", name, raw, default)
        return default


@dataclass(frozen=True)
class ImageFeatures:
    text_density: float
    aspect_ratio: float
    region_count: int
    has_columns: bool
    column_gap_strength: float
    line_peak_count: int


@dataclass(frozen=True)
class OcrStrategy:
    """Selected Tesseract/image config for one OCR pass."""

    bucket: str
    psm: str
    image_variant: str  # "standard" | "binarized"
    boundary_confidence: float  # 0..1; low → alternate-PSM fallback preferred
    alternate_psm: str
    features: ImageFeatures | None = None
    skip_tesseract: bool = False


# Static decision table — PSM 4 for multi_column is an unproven hypothesis
# (prior measurement found PSM 4 orphaned price columns on typical receipts;
# see ocr_engine._config comment). Validate via scripts/process_receipts.ps1
# before flipping ADAPTIVE_OCR_ENABLED on by default.
_BUCKET_STRATEGIES: dict[str, tuple[str, str, str]] = {
    # bucket → (psm, image_variant, alternate_psm)
    "default": ("6", "standard", "4"),
    "multi_column": ("4", "standard", "6"),
    "sparse": ("11", "standard", "6"),
    "near_blank": ("6", "standard", "6"),
}


def strategy_for_bucket(
    bucket: str, *, boundary_confidence: float = 1.0
) -> OcrStrategy:
    """Map a bucket name to an OcrStrategy (exhaustive table, pure)."""
    psm, variant, alt = _BUCKET_STRATEGIES.get(bucket, _BUCKET_STRATEGIES["default"])
    return OcrStrategy(
        bucket=bucket if bucket in _BUCKET_STRATEGIES else "default",
        psm=psm,
        image_variant=variant,
        boundary_confidence=boundary_confidence,
        alternate_psm=alt,
        skip_tesseract=(bucket == "near_blank"),
    )


def _to_gray(image: np.ndarray) -> np.ndarray:
    if image.ndim == 3:
        return cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    return image


def _measurement_mask(gray: np.ndarray) -> np.ndarray:
    """Otsu ink mask used only for feature measurement, never fed to Tesseract."""
    _, thresh = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY_INV | cv2.THRESH_OTSU)
    return thresh


def _column_gap_strength(mask: np.ndarray) -> tuple[bool, float]:
    """Detect a sustained low-density vertical gap splitting the width."""
    h, w = mask.shape[:2]
    if w < 20 or h < 20:
        return False, 0.0
    profile = np.sum(mask > 0, axis=0).astype(np.float64)
    max_peak = float(profile.max()) if profile.size else 0.0
    if max_peak <= 0:
        return False, 0.0
    low = profile < (max_peak * _COLUMN_GAP_MAX_DENSITY_FRACTION)
    min_gap = max(3, int(w * _COLUMN_GAP_MIN_WIDTH_FRACTION))
    best = 0
    run = 0
    for is_low in low:
        if is_low:
            run += 1
            best = max(best, run)
        else:
            run = 0
    # Gap must not be at the extreme edges (margin padding), and must split
    # the profile into ink on both sides.
    if best < min_gap:
        return False, 0.0
    # Find the longest gap's center and require ink on both sides.
    run = 0
    gap_start = 0
    best_start = 0
    best_len = 0
    for i, is_low in enumerate(low):
        if is_low:
            if run == 0:
                gap_start = i
            run += 1
            if run > best_len:
                best_len = run
                best_start = gap_start
        else:
            run = 0
    gap_end = best_start + best_len
    left_ink = float(np.sum(profile[:best_start]))
    right_ink = float(np.sum(profile[gap_end:]))
    if left_ink < max_peak or right_ink < max_peak:
        return False, 0.0
    # Strength: how wide the gap is relative to the minimum, capped at 1.
    strength = min(1.0, best_len / (min_gap * 2.0))
    return True, strength


def _line_peak_count(mask: np.ndarray) -> int:
    h, w = mask.shape[:2]
    if h < 10:
        return 0
    profile = np.sum(mask > 0, axis=1).astype(np.float64)
    max_peak = float(profile.max()) if profile.size else 0.0
    if max_peak <= 0:
        return 0
    threshold = max_peak * 0.25
    peaks = 0
    in_peak = False
    for v in profile:
        if v >= threshold:
            if not in_peak:
                peaks += 1
                in_peak = True
        else:
            in_peak = False
    return peaks


def extract_features(image: np.ndarray) -> ImageFeatures:
    """Compute geometric/density features from a preprocessed grayscale image."""
    gray = _to_gray(image)
    h, w = gray.shape[:2]
    aspect = (w / h) if h else 0.0
    mask = _measurement_mask(gray)
    density = float(np.mean(mask > 0)) if mask.size else 0.0
    # connectedComponentsWithStats: label 0 is background — subtract it.
    num_labels, _, stats, _ = cv2.connectedComponentsWithStats(mask, connectivity=8)
    # Filter tiny noise components (< 4 px area).
    regions = 0
    for i in range(1, num_labels):
        if int(stats[i, cv2.CC_STAT_AREA]) >= 4:
            regions += 1
    has_cols, gap_strength = _column_gap_strength(mask)
    return ImageFeatures(
        text_density=density,
        aspect_ratio=aspect,
        region_count=regions,
        has_columns=has_cols,
        column_gap_strength=gap_strength,
        line_peak_count=_line_peak_count(mask),
    )


def _boundary_confidence_for(features: ImageFeatures, bucket: str) -> float:
    """How far feature values sit from the decision thresholds (1 = clear)."""
    near_blank_d = _safe_float_env(
        "ADAPTIVE_OCR_NEAR_BLANK_DENSITY", _NEAR_BLANK_DENSITY
    )
    sparse_d = _safe_float_env("ADAPTIVE_OCR_SPARSE_DENSITY", _SPARSE_DENSITY)

    margins: list[float] = []
    if bucket == "near_blank":
        margins.append(1.0 - min(1.0, features.text_density / max(near_blank_d, 1e-9)))
    elif bucket == "sparse":
        # Distance from both the near-blank floor and the normal-density ceiling.
        above_blank = (features.text_density - near_blank_d) / max(
            sparse_d - near_blank_d, 1e-9
        )
        below_normal = (sparse_d - features.text_density) / max(sparse_d, 1e-9)
        margins.append(min(max(above_blank, 0.0), 1.0))
        margins.append(min(max(below_normal, 0.0), 1.0))
    elif bucket == "multi_column":
        margins.append(features.column_gap_strength)
    else:
        # default: distance from sparse and column thresholds
        above_sparse = (features.text_density - sparse_d) / max(sparse_d, 1e-9)
        margins.append(min(max(above_sparse, 0.0), 1.0))
        margins.append(1.0 - features.column_gap_strength)

    if not margins:
        return 1.0
    # Map the worst (closest-to-boundary) margin through a soft curve.
    worst = min(margins)
    if worst < _BOUNDARY_MARGIN:
        return max(0.0, worst / _BOUNDARY_MARGIN) * 0.5
    return 0.5 + 0.5 * min(1.0, (worst - _BOUNDARY_MARGIN) / (1.0 - _BOUNDARY_MARGIN))


def classify_receipt_image(image: np.ndarray) -> OcrStrategy:
    """Classify a preprocessed image into an OCR strategy bucket.

    Never raises — returns the default PSM-6/standard strategy on any error.
    """
    try:
        if image is None or not hasattr(image, "shape") or image.size == 0:
            logger.warning("classifier: empty/invalid image — default strategy")
            return strategy_for_bucket("default", boundary_confidence=0.0)

        h, w = image.shape[:2]
        if h < 2 or w < 2:
            logger.warning(
                "classifier: degenerate image %dx%d — default strategy", w, h
            )
            return strategy_for_bucket("default", boundary_confidence=0.0)

        features = extract_features(image)
        near_blank_d = _safe_float_env(
            "ADAPTIVE_OCR_NEAR_BLANK_DENSITY", _NEAR_BLANK_DENSITY
        )
        near_blank_r = int(
            _safe_float_env(
                "ADAPTIVE_OCR_NEAR_BLANK_REGIONS", float(_NEAR_BLANK_REGIONS)
            )
        )
        sparse_d = _safe_float_env("ADAPTIVE_OCR_SPARSE_DENSITY", _SPARSE_DENSITY)
        sparse_r = int(
            _safe_float_env("ADAPTIVE_OCR_SPARSE_REGIONS", float(_SPARSE_REGIONS))
        )

        if (
            features.text_density <= near_blank_d
            and features.region_count <= near_blank_r
        ):
            bucket = "near_blank"
        elif features.has_columns and features.column_gap_strength >= 0.4:
            bucket = "multi_column"
        elif features.text_density <= sparse_d and features.region_count <= sparse_r:
            bucket = "sparse"
        else:
            bucket = "default"

        confidence = _boundary_confidence_for(features, bucket)
        strategy = strategy_for_bucket(bucket, boundary_confidence=confidence)
        # Re-attach features (strategy_for_bucket doesn't take them).
        strategy = OcrStrategy(
            bucket=strategy.bucket,
            psm=strategy.psm,
            image_variant=strategy.image_variant,
            boundary_confidence=strategy.boundary_confidence,
            alternate_psm=strategy.alternate_psm,
            features=features,
            skip_tesseract=strategy.skip_tesseract,
        )
        logger.info(
            "classifier: bucket=%s psm=%s boundary=%.2f "
            "density=%.4f regions=%d columns=%s gap=%.2f lines=%d",
            strategy.bucket,
            strategy.psm,
            strategy.boundary_confidence,
            features.text_density,
            features.region_count,
            features.has_columns,
            features.column_gap_strength,
            features.line_peak_count,
        )
        return strategy
    except Exception:
        logger.exception("classifier: failed — falling back to default strategy")
        return strategy_for_bucket("default", boundary_confidence=0.0)
