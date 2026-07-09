import io

import pytest
from PIL import Image, ImageDraw


def _render_receipt_text() -> Image.Image:
    img = Image.new("L", (400, 300), color=255)
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
