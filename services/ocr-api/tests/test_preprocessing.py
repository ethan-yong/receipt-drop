import numpy as np
import pytest

from app.preprocessing import (
    InvalidImageError,
    _skew_angle,
    binarize,
    decode_image,
    deskew,
    enhance_contrast,
    preprocess,
    upscale_for_ocr,
)


def test_preprocess_raises_on_garbage_bytes() -> None:
    with pytest.raises(InvalidImageError):
        preprocess(b"not an image")


def test_deskew_reduces_skew_angle(skewed_low_contrast_image_bytes: bytes) -> None:
    image = decode_image(skewed_low_contrast_image_bytes)
    original_angle = _skew_angle(
        np.ascontiguousarray(image[:, :, 0])
        if image.ndim == 3
        else image
    )

    rotated = deskew(image)
    residual_angle = _skew_angle(
        np.ascontiguousarray(rotated[:, :, 0]) if rotated.ndim == 3 else rotated
    )

    assert abs(residual_angle) < abs(original_angle) or abs(residual_angle) < 2.0


def test_enhance_contrast_increases_std(skewed_low_contrast_image_bytes: bytes) -> None:
    image = decode_image(skewed_low_contrast_image_bytes)
    gray = image[:, :, 0] if image.ndim == 3 else image

    enhanced = enhance_contrast(image)

    assert enhanced.std() >= gray.std()


def test_binarize_outputs_only_black_and_white(
    skewed_low_contrast_image_bytes: bytes,
) -> None:
    image = decode_image(skewed_low_contrast_image_bytes)
    binary = binarize(enhance_contrast(image))

    assert set(np.unique(binary)).issubset({0, 255})


def test_preprocess_returns_grayscale_image(
    skewed_low_contrast_image_bytes: bytes,
) -> None:
    # Grayscale only — no CLAHE/binarization; Tesseract thresholds internally.
    processed = preprocess(skewed_low_contrast_image_bytes)

    assert processed.ndim == 2
    assert len(np.unique(processed)) > 2


def test_upscale_widens_narrow_image() -> None:
    # A 200×400 BGR image (width 200) should be scaled to at least 1500px wide.
    narrow = np.zeros((400, 200, 3), dtype=np.uint8)
    result = upscale_for_ocr(narrow, min_width=1500)

    assert result.shape[1] >= 1500
    # Aspect ratio preserved within 1 pixel of the ideal proportional height.
    scale = 1500 / 200
    expected_h = int(400 * scale)
    assert abs(result.shape[0] - expected_h) <= 1


def test_upscale_skips_wide_image() -> None:
    # An image already at or above min_width must be returned unchanged.
    wide = np.zeros((3000, 2000, 3), dtype=np.uint8)
    result = upscale_for_ocr(wide, min_width=1500)

    assert result is wide  # same object, no copy made
