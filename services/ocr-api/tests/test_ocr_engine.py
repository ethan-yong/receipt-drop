import numpy as np
import pytest

from app import ocr_engine


def _fake_data(
    words: list[tuple[str, int, tuple[int, int, int]]]
    | list[tuple[str, int, tuple[int, int, int], int]],
) -> dict[str, list]:
    """Builds an image_to_data DICT from (text, conf, (block, par, line)[, height]).

    Height defaults to 20 when omitted — existing 3-tuple call sites don't
    care about height_ratio and shouldn't need updating for it.
    """
    return {
        "text": [w[0] for w in words],
        "conf": [w[1] for w in words],
        "block_num": [w[2][0] for w in words],
        "par_num": [w[2][1] for w in words],
        "line_num": [w[2][2] for w in words],
        "height": [w[3] if len(w) > 3 else 20 for w in words],
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


def test_run_ocr_retries_with_binarize_on_low_confidence(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    low_conf_data = _fake_data([("blah", 20, (1, 1, 1))])
    high_conf_data = _fake_data([("ITEM", 90, (1, 1, 1)), ("7.00", 90, (1, 1, 2))])

    calls = []

    def fake_image_to_data(image, **_kwargs):
        calls.append(image)
        # First call sees the plain image, second sees the binarized one.
        return low_conf_data if len(calls) == 1 else high_conf_data

    monkeypatch.setattr(ocr_engine.pytesseract, "image_to_data", fake_image_to_data)
    monkeypatch.setattr("app.preprocessing.shadow_binarize", lambda image: image + 1)
    monkeypatch.delenv("PREPROCESS_ADAPTIVE_BINARIZE", raising=False)

    text, confidence = ocr_engine.run_ocr(np.zeros((10, 10), dtype=np.uint8))

    assert len(calls) == 2
    assert text == "ITEM\n7.00"
    assert confidence == pytest.approx(ocr_engine._calibrate_confidence(0.90))


def test_run_ocr_skips_retry_when_confidence_already_high(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    high_conf_data = _fake_data([("ITEM", 95, (1, 1, 1))])
    calls = []

    def fake_image_to_data(image, **_kwargs):
        calls.append(image)
        return high_conf_data

    monkeypatch.setattr(ocr_engine.pytesseract, "image_to_data", fake_image_to_data)
    monkeypatch.delenv("PREPROCESS_ADAPTIVE_BINARIZE", raising=False)

    ocr_engine.run_ocr(np.zeros((10, 10), dtype=np.uint8))

    assert len(calls) == 1


def test_run_ocr_keeps_first_pass_when_retry_is_not_better(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    low_conf_data = _fake_data([("blah", 20, (1, 1, 1))])
    still_low_conf_data = _fake_data([("blah", 15, (1, 1, 1))])
    calls = []

    def fake_image_to_data(image, **_kwargs):
        calls.append(image)
        return low_conf_data if len(calls) == 1 else still_low_conf_data

    monkeypatch.setattr(ocr_engine.pytesseract, "image_to_data", fake_image_to_data)
    monkeypatch.setattr("app.preprocessing.shadow_binarize", lambda image: image + 1)
    monkeypatch.delenv("PREPROCESS_ADAPTIVE_BINARIZE", raising=False)

    text, confidence = ocr_engine.run_ocr(np.zeros((10, 10), dtype=np.uint8))

    assert len(calls) == 2
    assert text == "blah"
    assert confidence == pytest.approx(ocr_engine._calibrate_confidence(0.20))


def test_run_ocr_detailed_computes_height_ratio(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # A "header" line with tall glyphs (~41px median) and a "body" line with
    # normal-sized glyphs (~19px median), on a 200px-tall image — the header
    # line's height_ratio must come out noticeably larger, which is exactly
    # the signal the Dart merchant extractor uses to prefer a large-font
    # header/logo line over the uniform itemized body.
    data = _fake_data(
        [
            ("HEADER", 90, (1, 1, 1), 40),
            ("TEXT", 90, (1, 1, 1), 42),
            ("item", 90, (1, 1, 2), 20),
            ("price", 90, (1, 1, 2), 18),
        ]
    )
    monkeypatch.setattr(ocr_engine.pytesseract, "image_to_data", lambda *a, **k: data)

    lines, _ = ocr_engine.run_ocr_detailed(np.zeros((200, 100), dtype=np.uint8))

    assert len(lines) == 2
    header, body = lines
    assert header.text == "HEADER TEXT"
    assert header.height_ratio == pytest.approx(41 / 200)  # median of [40, 42]
    assert body.text == "item price"
    assert body.height_ratio == pytest.approx(19 / 200)  # median of [20, 18]
    assert header.height_ratio > body.height_ratio


def test_run_ocr_detailed_empty_returns_no_lines(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    data = _fake_data([("", -1, (1, 1, 1)), ("   ", -1, (1, 1, 1))])
    monkeypatch.setattr(ocr_engine.pytesseract, "image_to_data", lambda *a, **k: data)

    lines, confidence = ocr_engine.run_ocr_detailed(np.zeros((10, 10), dtype=np.uint8))

    assert lines == []
    assert confidence == 0.0
