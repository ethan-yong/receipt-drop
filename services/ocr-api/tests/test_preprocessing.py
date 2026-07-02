import numpy as np
import pytest

from app.preprocessing import (
    InvalidImageError,
    _skew_angle,
    decode_image,
    deskew,
    enhance_contrast,
    preprocess,
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
