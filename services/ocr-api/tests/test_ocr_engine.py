import numpy as np
import pytest

from app import ocr_engine


def _fake_data(
    words: list[tuple[str, int, tuple[int, int, int]]],
) -> dict[str, list]:
    """Builds an image_to_data DICT from (text, conf, (block, par, line)) rows."""
    return {
        "text": [w[0] for w in words],
        "conf": [w[1] for w in words],
        "block_num": [w[2][0] for w in words],
        "par_num": [w[2][1] for w in words],
        "line_num": [w[2][2] for w in words],
    }


def test_run_ocr_groups_words_into_lines(monkeypatch: pytest.MonkeyPatch) -> None:
    data = _fake_data(
        [
            ("", -1, (1, 1, 1)),  # structural row: no text, conf -1
            ("TEH", 85, (1, 1, 1)),
            ("TARIK", 95, (1, 1, 1)),
            ("2.50", 70, (1, 1, 2)),
        ]
    )
    monkeypatch.setattr(
        ocr_engine.pytesseract, "image_to_data", lambda *a, **k: data
    )

    text, confidence = ocr_engine.run_ocr(np.zeros((10, 10), dtype=np.uint8))

    assert text == "TEH TARIK\n2.50"
    raw_mean = (85 + 95 + 70) / 3 / 100.0
    assert confidence == pytest.approx(ocr_engine._calibrate_confidence(raw_mean))


def test_run_ocr_excludes_nonpositive_conf_from_mean(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    data = _fake_data(
        [
            ("RM", 80, (1, 1, 1)),
            ("7.70", 0, (1, 1, 1)),  # conf 0 = "no confidence", excluded
        ]
    )
    monkeypatch.setattr(
        ocr_engine.pytesseract, "image_to_data", lambda *a, **k: data
    )

    text, confidence = ocr_engine.run_ocr(np.zeros((10, 10), dtype=np.uint8))

    assert text == "RM 7.70"
    assert confidence == pytest.approx(ocr_engine._calibrate_confidence(0.80))


def test_run_ocr_preserves_block_order(monkeypatch: pytest.MonkeyPatch) -> None:
    data = _fake_data(
        [
            ("HEADER", 90, (1, 1, 1)),
            ("ITEM", 90, (2, 1, 1)),
            ("TOTAL", 90, (3, 1, 1)),
        ]
    )
    monkeypatch.setattr(
        ocr_engine.pytesseract, "image_to_data", lambda *a, **k: data
    )

    text, _ = ocr_engine.run_ocr(np.zeros((10, 10), dtype=np.uint8))

    assert text == "HEADER\nITEM\nTOTAL"


def test_run_ocr_empty_returns_zero(monkeypatch: pytest.MonkeyPatch) -> None:
    data = _fake_data([("", -1, (1, 1, 1)), ("   ", -1, (1, 1, 1))])
    monkeypatch.setattr(
        ocr_engine.pytesseract, "image_to_data", lambda *a, **k: data
    )

    assert ocr_engine.run_ocr(np.zeros((10, 10), dtype=np.uint8)) == ("", 0.0)


def test_config_includes_language_flag() -> None:
    # -l must be present regardless of which language is configured.
    assert "-l" in ocr_engine._config()


def test_calibrate_confidence_squashes_high_values() -> None:
    # Sigmoid with midpoint 0.75, steepness 8: raw 0.95 → ≈ 0.832.
    # The calibrated value must be strictly less than the raw input (de-inflation
    # happened) but not excessively squashed (still above 0.80).
    calibrated = ocr_engine._calibrate_confidence(0.95)
    assert 0.80 < calibrated < 0.95
