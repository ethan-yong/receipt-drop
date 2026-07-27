import io

import numpy as np
import pytest
from PIL import Image, ImageDraw


def _render_receipt_text(size: tuple[int, int] = (400, 300)) -> Image.Image:
    img = Image.new("L", size, color=255)
    draw = ImageDraw.Draw(img)
    lines = [
        "SAMPLE STORE",
        "123 MAIN ST",
        "MILK        RM 4.50",
        "BREAD       RM 3.20",
        "TOTAL       RM 7.70",
    ]
    y = 30
    for line in lines:
        draw.text((30, y), line, fill=0)
        y += 40
    return img


@pytest.fixture
def skewed_low_contrast_image() -> Image.Image:
    """A synthetic receipt image rotated ~8deg with reduced contrast, used to
    exercise the deskew/CLAHE preprocessing pipeline."""
    img = _render_receipt_text()
    rotated = img.rotate(8, expand=True, fillcolor=255)
    low_contrast = Image.blend(
        rotated.convert("L"),
        Image.new("L", rotated.size, color=128),
        alpha=0.4,
    )
    return low_contrast.convert("RGB")


@pytest.fixture
def skewed_low_contrast_image_bytes(skewed_low_contrast_image: Image.Image) -> bytes:
    buf = io.BytesIO()
    skewed_low_contrast_image.save(buf, format="PNG")
    return buf.getvalue()


@pytest.fixture
def clean_receipt_image() -> Image.Image:
    """Sharp, high-contrast, unrotated receipt — stands in for a clean scan.

    PDFs never reach ocr-api (client-side text extraction); this is the image
    equivalent of an already-clean input that must not be degraded by defaults.
    Dense ink coverage keeps grayscale std-dev above the CLAHE gate threshold.
    """
    img = Image.new("L", (400, 300), color=245)
    draw = ImageDraw.Draw(img)
    lines = [
        "SAMPLE STORE",
        "123 MAIN ST",
        "MILK        RM 4.50",
        "BREAD       RM 3.20",
        "EGGS        RM 5.10",
        "RICE        RM 12.00",
        "COFFEE      RM 8.50",
        "TOTAL       RM 33.30",
    ]
    y = 20
    for line in lines:
        draw.text((20, y), line, fill=0)
        draw.rectangle((18, y + 18, 380, y + 22), fill=0)
        y += 32
    return img.convert("RGB")


@pytest.fixture
def clean_receipt_image_bytes(clean_receipt_image: Image.Image) -> bytes:
    buf = io.BytesIO()
    clean_receipt_image.save(buf, format="PNG")
    return buf.getvalue()


@pytest.fixture
def low_light_receipt_image(skewed_low_contrast_image: Image.Image) -> Image.Image:
    """Underexposed variant of the low-contrast fixture."""
    darkened = Image.blend(
        skewed_low_contrast_image.convert("L"),
        Image.new("L", skewed_low_contrast_image.size, color=0),
        alpha=0.35,
    )
    return darkened.convert("RGB")


@pytest.fixture
def low_light_receipt_image_bytes(low_light_receipt_image: Image.Image) -> bytes:
    buf = io.BytesIO()
    low_light_receipt_image.save(buf, format="PNG")
    return buf.getvalue()


@pytest.fixture
def low_resolution_receipt_image() -> Image.Image:
    """Small receipt (~300px wide) to exercise upscale_for_ocr with new stages."""
    return _render_receipt_text((300, 225)).convert("RGB")


@pytest.fixture
def low_resolution_receipt_image_bytes(
    low_resolution_receipt_image: Image.Image,
) -> bytes:
    buf = io.BytesIO()
    low_resolution_receipt_image.save(buf, format="PNG")
    return buf.getvalue()


@pytest.fixture
def angled_receipt_on_background() -> Image.Image:
    """Receipt pasted onto a larger contrasting canvas with a visible border."""
    receipt = _render_receipt_text((320, 240)).convert("RGB")
    canvas = Image.new("RGB", (640, 480), color=(40, 40, 40))
    # Paste receipt with a white mat so Canny can find document edges.
    mat = Image.new("RGB", (360, 280), color=(255, 255, 255))
    canvas.paste(mat, (140, 100))
    canvas.paste(receipt, (160, 120))
    rotated = canvas.rotate(12, expand=True, fillcolor=(40, 40, 40))
    return rotated


@pytest.fixture
def angled_receipt_on_background_bytes(
    angled_receipt_on_background: Image.Image,
) -> bytes:
    buf = io.BytesIO()
    angled_receipt_on_background.save(buf, format="PNG")
    return buf.getvalue()


@pytest.fixture
def shadow_gradient_receipt_image(clean_receipt_image: Image.Image) -> Image.Image:
    """Receipt with a horizontal brightness gradient simulating hand shadow."""
    arr = np.array(clean_receipt_image.convert("L"), dtype=np.float32)
    height, width = arr.shape
    gradient = np.linspace(0.45, 1.0, width, dtype=np.float32)
    shaded = np.clip(arr * gradient[np.newaxis, :], 0, 255).astype(np.uint8)
    return Image.fromarray(shaded).convert("RGB")


@pytest.fixture
def shadow_gradient_receipt_image_bytes(
    shadow_gradient_receipt_image: Image.Image,
) -> bytes:
    buf = io.BytesIO()
    shadow_gradient_receipt_image.save(buf, format="PNG")
    return buf.getvalue()


@pytest.fixture
def faded_receipt_image() -> Image.Image:
    """Low-contrast receipt — bimodality guard rejects aggressive correction."""
    base = _render_receipt_text().convert("L")
    faded = Image.blend(base, Image.new("L", base.size, color=200), alpha=0.85)
    return faded.convert("RGB")


@pytest.fixture
def faded_receipt_image_bytes(faded_receipt_image: Image.Image) -> bytes:
    buf = io.BytesIO()
    faded_receipt_image.save(buf, format="PNG")
    return buf.getvalue()
