import numpy as np
import pytest

from ocr_api import ocr_engine


def _fake_data(
    words: list[tuple[str, int, tuple[int, int, int]]]
    | list[tuple[str, int, tuple[int, int, int], int]]
    | list[tuple[str, int, tuple[int, int, int], int, int, int, int]],
) -> dict[str, list]:
    """Build image_to_data DICT from word tuples.

    Each word is (text, conf, (block, par, line)[, height[, left, top, width]]).
    Height defaults to 20 when omitted; left/top/width default to 0/0/10.
    """

    def _word_fields(w: tuple) -> tuple[int, int, int, int]:
        height = w[3] if len(w) > 3 else 20
        left = w[4] if len(w) > 4 else 0
        top = w[5] if len(w) > 5 else 0
        width = w[6] if len(w) > 6 else 10
        return height, left, top, width

    parsed = [_word_fields(w) for w in words]
    return {
        "text": [w[0] for w in words],
        "conf": [w[1] for w in words],
        "block_num": [w[2][0] for w in words],
        "par_num": [w[2][1] for w in words],
        "line_num": [w[2][2] for w in words],
        "height": [p[0] for p in parsed],
        "left": [p[1] for p in parsed],
        "top": [p[2] for p in parsed],
        "width": [p[3] for p in parsed],
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
    monkeypatch.setattr(ocr_engine.pytesseract, "image_to_data", lambda *a, **k: data)

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
    monkeypatch.setattr(ocr_engine.pytesseract, "image_to_data", lambda *a, **k: data)

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
    monkeypatch.setattr(ocr_engine.pytesseract, "image_to_data", lambda *a, **k: data)

    text, _ = ocr_engine.run_ocr(np.zeros((10, 10), dtype=np.uint8))

    assert text == "HEADER\nITEM\nTOTAL"


def test_run_ocr_empty_returns_zero(monkeypatch: pytest.MonkeyPatch) -> None:
    data = _fake_data([("", -1, (1, 1, 1)), ("   ", -1, (1, 1, 1))])
    monkeypatch.setattr(ocr_engine.pytesseract, "image_to_data", lambda *a, **k: data)

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
    monkeypatch.setattr(
        "ocr_api.preprocessing.shadow_binarize", lambda image: image + 1
    )
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
    monkeypatch.setattr(
        "ocr_api.preprocessing.shadow_binarize", lambda image: image + 1
    )
    monkeypatch.delenv("PREPROCESS_ADAPTIVE_BINARIZE", raising=False)

    text, confidence = ocr_engine.run_ocr(np.zeros((10, 10), dtype=np.uint8))

    assert len(calls) == 2
    assert text == "blah"
    assert confidence == pytest.approx(ocr_engine._calibrate_confidence(0.20))


def test_run_ocr_skips_retry_when_plain_pass_is_already_slow(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    low_conf_data = _fake_data([("blah", 20, (1, 1, 1))])
    calls = []

    def fake_image_to_data(image, **_kwargs):
        calls.append(image)
        return low_conf_data

    monkeypatch.setattr(ocr_engine.pytesseract, "image_to_data", fake_image_to_data)
    monkeypatch.delenv("PREPROCESS_ADAPTIVE_BINARIZE", raising=False)

    # plain_start=0.0, _run_tesseract's own start/elapsed=0.0 (unused by the
    # budget check), plain_elapsed = 25.0 - 0.0 = 25.0s >= the 20s budget.
    perf_values = iter([0.0, 0.0, 0.0, 25.0])
    monkeypatch.setattr(ocr_engine.time, "perf_counter", lambda: next(perf_values))

    text, confidence = ocr_engine.run_ocr(np.zeros((10, 10), dtype=np.uint8))

    assert len(calls) == 1  # binarize retry never ran
    assert text == "blah"
    assert confidence == pytest.approx(ocr_engine._calibrate_confidence(0.20))


def test_run_ocr_still_retries_when_plain_pass_is_fast(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    low_conf_data = _fake_data([("blah", 20, (1, 1, 1))])
    high_conf_data = _fake_data([("ITEM", 90, (1, 1, 1)), ("7.00", 90, (1, 1, 2))])
    calls = []

    def fake_image_to_data(image, **_kwargs):
        calls.append(image)
        return low_conf_data if len(calls) == 1 else high_conf_data

    monkeypatch.setattr(ocr_engine.pytesseract, "image_to_data", fake_image_to_data)
    monkeypatch.setattr(
        "ocr_api.preprocessing.shadow_binarize", lambda image: image + 1
    )
    monkeypatch.delenv("PREPROCESS_ADAPTIVE_BINARIZE", raising=False)

    # plain_elapsed = 5.0 - 0.0 = 5.0s, under the 20s budget, so retry proceeds
    # same as today's behavior. Two extra values (5.0, 6.0) cover the retry
    # pass's own start/elapsed perf_counter() calls.
    perf_values = iter([0.0, 0.0, 0.0, 5.0, 5.0, 6.0])
    monkeypatch.setattr(ocr_engine.time, "perf_counter", lambda: next(perf_values))

    text, confidence = ocr_engine.run_ocr(np.zeros((10, 10), dtype=np.uint8))

    assert len(calls) == 2  # binarize retry did run
    assert text == "ITEM\n7.00"
    assert confidence == pytest.approx(ocr_engine._calibrate_confidence(0.90))


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

    result = ocr_engine.run_ocr_detailed(np.zeros((200, 100), dtype=np.uint8))
    lines = result.lines

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

    result = ocr_engine.run_ocr_detailed(np.zeros((10, 10), dtype=np.uint8))

    assert result.lines == []
    assert result.confidence == 0.0


def test_run_ocr_detailed_computes_per_line_confidence(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # A confident header line (90/95) and a much less confident body line
    # (20/30) — each line's own calibrated confidence must diverge from the
    # other and from the overall request mean, since this is exactly the
    # signal the LLM cleanup prompt uses to focus correction effort.
    data = _fake_data(
        [
            ("HEADER", 90, (1, 1, 1)),
            ("TEXT", 95, (1, 1, 1)),
            ("blah", 20, (1, 1, 2)),
            ("blur", 30, (1, 1, 2)),
        ]
    )
    monkeypatch.setattr(ocr_engine.pytesseract, "image_to_data", lambda *a, **k: data)

    result = ocr_engine.run_ocr_detailed(np.zeros((10, 10), dtype=np.uint8))
    lines = result.lines
    mean_confidence = result.confidence

    assert len(lines) == 2
    header, body = lines
    assert header.confidence == pytest.approx(
        ocr_engine._calibrate_confidence((90 + 95) / 2 / 100.0)
    )
    assert body.confidence == pytest.approx(
        ocr_engine._calibrate_confidence((20 + 30) / 2 / 100.0)
    )
    assert header.confidence > body.confidence
    # Per-line confidences bracket the overall calibrated mean.
    assert body.confidence < mean_confidence < header.confidence


def test_ocr_line_result_confidence_defaults_to_fully_confident() -> None:
    # Call sites that don't care about confidence (most existing /ocr route
    # tests) shouldn't need to specify it — default is "assume no correction
    # needed" (1.0), not "assume worst" (0.0), since an unspecified value
    # means "irrelevant to this test," not "known low-quality."
    line = ocr_engine.OcrLineResult(text="TOTAL RM 7.70", height_ratio=0.05)
    assert line.confidence == 1.0


def test_run_ocr_detailed_computes_line_bbox_ratios(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Two words on one line at left=10,width=20 and left=40,width=30 on a 100x200 image.
    data = _fake_data(
        [
            ("FOO", 90, (1, 1, 1), 20, 10, 5, 20),
            ("BAR", 90, (1, 1, 1), 20, 40, 5, 30),
            ("BAZ", 90, (1, 1, 2), 20, 5, 50, 15),
        ]
    )
    monkeypatch.setattr(ocr_engine.pytesseract, "image_to_data", lambda *a, **k: data)

    result = ocr_engine.run_ocr_detailed(np.zeros((200, 100), dtype=np.uint8))
    lines = result.lines

    assert len(lines) == 2
    first, second = lines
    assert first.left_ratio == pytest.approx(10 / 100)
    assert first.top_ratio == pytest.approx(5 / 200)
    assert first.width_ratio == pytest.approx((70 - 10) / 100)
    assert second.left_ratio == pytest.approx(5 / 100)
    assert second.width_ratio == pytest.approx(15 / 100)


def test_config_accepts_explicit_psm() -> None:
    assert "--psm 4" in ocr_engine._config(psm="4")
    assert "--psm 11" in ocr_engine._config(psm="11")
    assert "--psm 6" in ocr_engine._config(psm=None) or "psm" in ocr_engine._config()


def test_adaptive_alt_psm_retry_on_ambiguous_boundary(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from ocr_api.receipt_classifier import OcrStrategy

    low_conf = _fake_data([("blah", 20, (1, 1, 1))])
    better = _fake_data(
        [
            ("SAMPLE", 90, (1, 1, 1)),
            ("TOTAL", 90, (1, 1, 2)),
            ("RM", 90, (1, 1, 2)),
            ("7.70", 90, (1, 1, 2)),
        ]
    )
    configs: list[str] = []

    def fake_image_to_data(image, **kwargs):
        configs.append(kwargs.get("config", ""))
        return low_conf if len(configs) == 1 else better

    monkeypatch.setenv("ADAPTIVE_OCR_ENABLED", "1")
    monkeypatch.delenv("PREPROCESS_ADAPTIVE_BINARIZE", raising=False)
    monkeypatch.setattr(ocr_engine.pytesseract, "image_to_data", fake_image_to_data)
    monkeypatch.setattr(
        "ocr_api.receipt_classifier.classify_receipt_image",
        lambda _img: OcrStrategy(
            bucket="default",
            psm="6",
            image_variant="standard",
            boundary_confidence=0.2,  # ambiguous → alternate PSM
            alternate_psm="4",
        ),
    )
    # Force pass 1 below good-enough so retry fires.
    monkeypatch.setenv("ADAPTIVE_OCR_GOOD_ENOUGH_SCORE", "0.95")

    result = ocr_engine.run_ocr_detailed(np.zeros((100, 50), dtype=np.uint8))

    assert len(configs) == 2
    assert "--psm 6" in configs[0]
    assert "--psm 4" in configs[1]
    assert result.strategy_bucket == "default"
    assert result.pass_count == 2
    assert "TOTAL" in "\n".join(line.text for line in result.lines)


def test_adaptive_binarize_retry_on_confident_boundary(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from ocr_api.receipt_classifier import OcrStrategy

    low_conf = _fake_data([("blah", 20, (1, 1, 1))])
    better = _fake_data(
        [
            ("ITEM", 90, (1, 1, 1)),
            ("TOTAL", 90, (1, 1, 2)),
            ("RM", 90, (1, 1, 2)),
            ("5.00", 90, (1, 1, 2)),
        ]
    )
    images: list = []

    def fake_image_to_data(image, **_kwargs):
        images.append(image)
        return low_conf if len(images) == 1 else better

    monkeypatch.setenv("ADAPTIVE_OCR_ENABLED", "1")
    monkeypatch.delenv("PREPROCESS_ADAPTIVE_BINARIZE", raising=False)
    monkeypatch.setenv("ADAPTIVE_OCR_GOOD_ENOUGH_SCORE", "0.95")
    monkeypatch.setattr(ocr_engine.pytesseract, "image_to_data", fake_image_to_data)
    monkeypatch.setattr(
        "ocr_api.preprocessing.shadow_binarize", lambda image: image + 1
    )
    monkeypatch.setattr(
        "ocr_api.receipt_classifier.classify_receipt_image",
        lambda _img: OcrStrategy(
            bucket="default",
            psm="6",
            image_variant="standard",
            boundary_confidence=0.9,  # confident → binarize
            alternate_psm="4",
        ),
    )

    result = ocr_engine.run_ocr_detailed(np.zeros((100, 50), dtype=np.uint8))

    assert len(images) == 2
    # Second pass must have used the binarized image (image + 1).
    assert not np.array_equal(images[0], images[1])
    assert result.pass_count == 2
    assert result.strategy_psm == "6"


def test_adaptive_near_blank_skips_tesseract(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from ocr_api.receipt_classifier import OcrStrategy

    calls = []

    def fake_image_to_data(image, **_kwargs):
        calls.append(image)
        return _fake_data([("should", 90, (1, 1, 1))])

    monkeypatch.setenv("ADAPTIVE_OCR_ENABLED", "1")
    monkeypatch.setattr(ocr_engine.pytesseract, "image_to_data", fake_image_to_data)
    monkeypatch.setattr(
        "ocr_api.receipt_classifier.classify_receipt_image",
        lambda _img: OcrStrategy(
            bucket="near_blank",
            psm="6",
            image_variant="standard",
            boundary_confidence=1.0,
            alternate_psm="6",
            skip_tesseract=True,
        ),
    )

    result = ocr_engine.run_ocr_detailed(np.zeros((100, 50), dtype=np.uint8))

    assert calls == []
    assert result.lines == []
    assert result.pass_count == 0
    assert result.strategy_bucket == "near_blank"


def test_run_ocr_detailed_retains_per_word_confidence(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Word-level retention must not change line/request means (calibrate(mean),
    # not mean(calibrate)) — a regression here silently breaks every threshold.
    data = _fake_data(
        [
            ("TEH", 90, (1, 1, 1), 20, 10, 5, 20),
            ("TARIK", 80, (1, 1, 1), 20, 40, 5, 30),
            ("RM", 70, (1, 1, 2), 20, 5, 50, 15),
            ("2.50", 60, (1, 1, 2), 20, 30, 50, 25),
        ]
    )
    monkeypatch.setattr(ocr_engine.pytesseract, "image_to_data", lambda *a, **k: data)

    result = ocr_engine.run_ocr_detailed(np.zeros((200, 100), dtype=np.uint8))
    lines = result.lines

    assert len(lines) == 2
    header, body = lines
    assert len(header.words) == 2
    assert header.words[0].text == "TEH"
    assert header.words[0].confidence == pytest.approx(
        ocr_engine._calibrate_confidence(0.90)
    )
    assert header.words[0].left_ratio == pytest.approx(10 / 100)
    assert header.words[0].width_ratio == pytest.approx(20 / 100)
    assert header.words[0].digit_corrected is False
    assert header.words[1].text == "TARIK"
    # Line mean must still be calibrate(mean(raw)), not mean(calibrate(raw)).
    assert header.confidence == pytest.approx(
        ocr_engine._calibrate_confidence((90 + 80) / 2 / 100.0)
    )
    assert body.confidence == pytest.approx(
        ocr_engine._calibrate_confidence((70 + 60) / 2 / 100.0)
    )
    raw_mean = (90 + 80 + 70 + 60) / 4 / 100.0
    assert result.confidence == pytest.approx(
        ocr_engine._calibrate_confidence(raw_mean)
    )


def test_normalize_ocr_amount_words_flags_digit_corrected() -> None:
    words = [
        ocr_engine.OcrWordResult(text="TOTAL", confidence=0.9),
        ocr_engine.OcrWordResult(text="RM", confidence=0.85),
        ocr_engine.OcrWordResult(text="Z.50", confidence=0.7),
        ocr_engine.OcrWordResult(text="OK", confidence=0.95),
    ]
    text, out = ocr_engine._normalize_ocr_amount_words(words)
    assert text == "TOTAL RM 2.50 OK"
    assert out[0].digit_corrected is False
    assert out[1].digit_corrected is False
    assert out[2].text == "2.50"
    assert out[2].digit_corrected is True
    assert out[3].digit_corrected is False


def test_normalize_ocr_amount_words_no_correction_leaves_flags_false() -> None:
    words = [
        ocr_engine.OcrWordResult(text="RM", confidence=0.9),
        ocr_engine.OcrWordResult(text="7.70", confidence=0.9),
    ]
    text, out = ocr_engine._normalize_ocr_amount_words(words)
    assert text == "RM 7.70"
    assert all(not w.digit_corrected for w in out)


def test_public_ocr_line_selective_enrichment(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from ocr_api.main import _public_ocr_line
    from ocr_api.ocr_engine import OcrLineResult, OcrWordResult

    monkeypatch.setenv("TOKEN_LEVEL_CONFIDENCE", "1")
    monkeypatch.setenv("OCR_WORD_ENRICHMENT_THRESHOLD", "0.7")

    low = OcrLineResult(
        text="blurry",
        height_ratio=0.05,
        confidence=0.4,
        words=(OcrWordResult(text="blurry", confidence=0.4),),
    )
    high = OcrLineResult(
        text="CLEAR",
        height_ratio=0.05,
        confidence=0.9,
        words=(OcrWordResult(text="CLEAR", confidence=0.9),),
    )
    low_pub = _public_ocr_line(low)
    high_pub = _public_ocr_line(high)
    assert low_pub.confidence == pytest.approx(0.4)
    assert low_pub.words is not None and len(low_pub.words) == 1
    assert high_pub.confidence == pytest.approx(0.9)
    assert high_pub.words is None


def test_public_ocr_line_omits_confidence_when_flag_off(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from ocr_api.main import _public_ocr_line
    from ocr_api.ocr_engine import OcrLineResult

    monkeypatch.delenv("TOKEN_LEVEL_CONFIDENCE", raising=False)
    line = OcrLineResult(text="TOTAL", height_ratio=0.05, confidence=0.5)
    pub = _public_ocr_line(line)
    assert pub.confidence is None
    assert pub.words is None
