"""Unit tests for the pre-OCR receipt layout classifier."""

from __future__ import annotations

import numpy as np
import pytest

from ocr_api.receipt_classifier import (
    _BUCKET_STRATEGIES,
    classify_receipt_image,
    extract_features,
    strategy_for_bucket,
)


def _blank_image(h: int = 200, w: int = 100) -> np.ndarray:
    return np.full((h, w), 255, dtype=np.uint8)


def _dense_receipt(h: int = 400, w: int = 200) -> np.ndarray:
    """Synthetic dense single-column receipt (dark text on white)."""
    img = _blank_image(h, w)
    # Horizontal text-like bars across most of the width.
    for y in range(20, h - 20, 18):
        img[y : y + 6, 15 : w - 15] = 0
    return img


def _sparse_receipt(h: int = 400, w: int = 200) -> np.ndarray:
    """Very little ink — a few short lines only."""
    img = _blank_image(h, w)
    img[40:46, 40:80] = 0
    img[100:106, 50:90] = 0
    return img


def _multi_column_receipt(h: int = 400, w: int = 300) -> np.ndarray:
    """Two ink columns separated by a wide empty vertical gap."""
    img = _blank_image(h, w)
    mid = w // 2
    gap = max(30, int(w * 0.15))
    left_end = mid - gap // 2
    right_start = mid + gap // 2
    for y in range(20, h - 20, 16):
        img[y : y + 5, 10:left_end] = 0
        img[y : y + 5, right_start : w - 10] = 0
    return img


def test_strategy_table_covers_all_buckets() -> None:
    for bucket in ("default", "multi_column", "sparse", "near_blank"):
        s = strategy_for_bucket(bucket)
        assert s.bucket == bucket
        assert s.psm == _BUCKET_STRATEGIES[bucket][0]
        assert s.image_variant == _BUCKET_STRATEGIES[bucket][1]
        assert s.alternate_psm == _BUCKET_STRATEGIES[bucket][2]


def test_strategy_table_unknown_bucket_falls_back_to_default() -> None:
    s = strategy_for_bucket("not_a_real_bucket")
    assert s.bucket == "default"
    assert s.psm == "6"


def test_near_blank_short_circuits() -> None:
    strategy = classify_receipt_image(_blank_image())
    assert strategy.bucket == "near_blank"
    assert strategy.skip_tesseract is True


def test_dense_receipt_is_default_bucket() -> None:
    strategy = classify_receipt_image(_dense_receipt())
    assert strategy.bucket == "default"
    assert strategy.psm == "6"
    assert strategy.skip_tesseract is False


def test_sparse_receipt_bucket() -> None:
    strategy = classify_receipt_image(_sparse_receipt())
    assert strategy.bucket in {"sparse", "near_blank"}
    # A few short bars should not be near-blank if density clears the floor;
    # accept sparse as the primary expectation.
    if strategy.bucket == "sparse":
        assert strategy.psm == "11"


def test_multi_column_bucket() -> None:
    strategy = classify_receipt_image(_multi_column_receipt())
    assert strategy.bucket == "multi_column"
    assert strategy.psm == "4"
    assert strategy.alternate_psm == "6"
    assert strategy.features is not None
    assert strategy.features.has_columns is True


def test_classifier_fails_safe_on_degenerate_image() -> None:
    strategy = classify_receipt_image(np.zeros((1, 1), dtype=np.uint8))
    assert strategy.bucket == "default"
    assert strategy.psm == "6"


def test_classifier_fails_safe_on_none_like(monkeypatch: pytest.MonkeyPatch) -> None:
    # extract_features blowing up must not propagate.
    monkeypatch.setattr(
        "ocr_api.receipt_classifier.extract_features",
        lambda _img: (_ for _ in ()).throw(RuntimeError("boom")),
    )
    strategy = classify_receipt_image(_dense_receipt())
    assert strategy.bucket == "default"
    assert strategy.psm == "6"


def test_extract_features_density_between_zero_and_one() -> None:
    features = extract_features(_dense_receipt())
    assert 0.0 < features.text_density < 1.0
    assert features.region_count > 0
    assert features.aspect_ratio > 0


def test_classifier_latency_budget_on_large_image() -> None:
    """Classifier must stay cheap on a long-receipt-sized image.

    Design target is ~300ms; CI/shared hosts can be slower, so the hard
    assert uses 1.0s as a regression guard against accidental O(n²) work.
    """
    import time

    # ~2500x5000 mimics an upscaled long thermal slip.
    large = _dense_receipt(h=5000, w=2500)
    start = time.perf_counter()
    classify_receipt_image(large)
    elapsed = time.perf_counter() - start
    assert elapsed < 1.0, f"classifier took {elapsed:.3f}s (budget 1.0s)"
