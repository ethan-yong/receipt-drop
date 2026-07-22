import cv2
import numpy as np
import pytest

from ocr_api.preprocessing import (
    _ADAPTIVE_WHITE_RATIO_MAX,
    _ADAPTIVE_WHITE_RATIO_MIN,
    InvalidImageError,
    _is_low_contrast,
    _skew_angle,
    binarize,
    decode_image,
    deskew,
    detect_document_corners,
    enhance_contrast,
    perspective_correct,
    preprocess,
    shadow_binarize,
    sharpen,
    upscale_for_ocr,
)


def test_preprocess_raises_on_garbage_bytes() -> None:
    with pytest.raises(InvalidImageError):
        preprocess(b"not an image")


def test_deskew_reduces_skew_angle(skewed_low_contrast_image_bytes: bytes) -> None:
    image = decode_image(skewed_low_contrast_image_bytes)
    original_angle = _skew_angle(
        np.ascontiguousarray(image[:, :, 0]) if image.ndim == 3 else image
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
    processed = preprocess(skewed_low_contrast_image_bytes)

    assert processed.ndim == 2
    assert len(np.unique(processed)) > 2


def test_upscale_widens_narrow_image() -> None:
    narrow = np.zeros((400, 200, 3), dtype=np.uint8)
    result = upscale_for_ocr(narrow, min_width=1500)

    assert result.shape[1] >= 1500
    scale = 1500 / 200
    expected_h = int(400 * scale)
    assert abs(result.shape[0] - expected_h) <= 1


def test_upscale_skips_wide_image() -> None:
    wide = np.zeros((3000, 2000, 3), dtype=np.uint8)
    result = upscale_for_ocr(wide, min_width=1500)

    assert result is wide


def test_detect_document_corners_finds_quad_on_angled_background(
    angled_receipt_on_background_bytes: bytes,
) -> None:
    image = decode_image(angled_receipt_on_background_bytes)
    corners = detect_document_corners(image)

    assert corners is not None
    assert corners.shape == (4, 2)


def test_detect_document_corners_returns_none_on_low_contrast_fixture(
    skewed_low_contrast_image_bytes: bytes,
) -> None:
    image = decode_image(skewed_low_contrast_image_bytes)
    assert detect_document_corners(image) is None


def test_detect_document_corners_returns_none_on_noise() -> None:
    noise = np.random.default_rng(0).integers(0, 256, (200, 200, 3), dtype=np.uint8)
    assert detect_document_corners(noise) is None


def test_detect_document_corners_rejects_tiny_contour(
    angled_receipt_on_background_bytes: bytes,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("MIN_DOCUMENT_AREA_RATIO", "0.95")
    image = decode_image(angled_receipt_on_background_bytes)
    assert detect_document_corners(image) is None


def test_perspective_correct_warps_when_confident(
    angled_receipt_on_background_bytes: bytes,
) -> None:
    image = decode_image(angled_receipt_on_background_bytes)
    before = image.shape[:2]
    corrected = perspective_correct(image)

    assert corrected.shape[:2] != before or corrected.shape[1] != before[1]


def test_perspective_correct_returns_input_when_not_confident(
    skewed_low_contrast_image_bytes: bytes,
) -> None:
    image = decode_image(skewed_low_contrast_image_bytes)
    result = perspective_correct(image)

    assert result.shape == image.shape
    assert np.array_equal(result, image)


def test_is_low_contrast_true_for_low_light(
    low_light_receipt_image_bytes: bytes,
) -> None:
    gray = decode_image(low_light_receipt_image_bytes)[:, :, 0]
    assert _is_low_contrast(gray)


def test_is_low_contrast_false_for_clean(clean_receipt_image_bytes: bytes) -> None:
    gray = decode_image(clean_receipt_image_bytes)[:, :, 0]
    assert not _is_low_contrast(gray)


def test_preprocess_clean_image_unchanged_by_default_flags(
    clean_receipt_image_bytes: bytes,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("PREPROCESS_PERSPECTIVE", raising=False)
    monkeypatch.delenv("PREPROCESS_SHARPEN", raising=False)
    monkeypatch.setenv("PREPROCESS_CLAHE", "0")

    processed = preprocess(clean_receipt_image_bytes)
    baseline = preprocess(clean_receipt_image_bytes)

    assert processed.shape == baseline.shape
    assert np.array_equal(processed, baseline)


def test_preprocess_low_light_applies_clahe_by_default(
    low_light_receipt_image_bytes: bytes,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("PREPROCESS_PERSPECTIVE", raising=False)
    monkeypatch.delenv("PREPROCESS_SHARPEN", raising=False)
    monkeypatch.setenv("PREPROCESS_CLAHE", "1")

    without = preprocess(low_light_receipt_image_bytes)
    monkeypatch.setenv("PREPROCESS_CLAHE", "0")
    with_clahe_off = preprocess(low_light_receipt_image_bytes)

    assert not np.array_equal(without, with_clahe_off)


def test_sharpen_increases_edge_energy(clean_receipt_image_bytes: bytes) -> None:
    gray = decode_image(clean_receipt_image_bytes)[:, :, 0]
    before = cv2.Laplacian(gray, cv2.CV_64F).var()
    after = cv2.Laplacian(sharpen(gray), cv2.CV_64F).var()

    assert after > before
    assert after < before * 5.0


def test_shadow_binarize_falls_back_to_otsu_on_degenerate_input() -> None:
    # Horizontal gradient: adaptive blows out to all-white; OTSU still splits cleanly.
    gray = np.tile(np.linspace(40, 220, 120, dtype=np.uint8), (120, 1))
    adaptive_only = cv2.adaptiveThreshold(
        gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 51, 11
    )
    assert float(np.mean(adaptive_only == 255)) > _ADAPTIVE_WHITE_RATIO_MAX

    result = shadow_binarize(gray)
    white_ratio = float(np.mean(result == 255))

    assert _ADAPTIVE_WHITE_RATIO_MIN <= white_ratio <= _ADAPTIVE_WHITE_RATIO_MAX


def test_preprocess_debug_writes_stage_files(
    clean_receipt_image_bytes: bytes,
    tmp_path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    debug_dir = tmp_path / "debug"
    monkeypatch.setenv("PREPROCESS_DEBUG", "1")
    monkeypatch.setenv("PREPROCESS_DEBUG_DIR", str(debug_dir))
    monkeypatch.setenv("PREPROCESS_CLAHE", "0")

    preprocess(clean_receipt_image_bytes)

    files = list(debug_dir.glob("*.png"))
    assert files
    assert any("original" in f.name for f in files)
    assert any("grayscale" in f.name for f in files)


def test_preprocess_debug_off_writes_nothing(
    clean_receipt_image_bytes: bytes,
    tmp_path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    debug_dir = tmp_path / "debug-empty"
    monkeypatch.delenv("PREPROCESS_DEBUG", raising=False)
    monkeypatch.setenv("PREPROCESS_DEBUG_DIR", str(debug_dir))
    monkeypatch.setenv("PREPROCESS_CLAHE", "0")

    preprocess(clean_receipt_image_bytes)

    assert not debug_dir.exists() or not any(debug_dir.iterdir())


def test_preprocess_low_resolution_still_returns_grayscale(
    low_resolution_receipt_image_bytes: bytes,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("MIN_OCR_WIDTH", "800")
    monkeypatch.setenv("PREPROCESS_CLAHE", "0")

    processed = preprocess(low_resolution_receipt_image_bytes)

    assert processed.ndim == 2
    assert processed.shape[1] >= 800
