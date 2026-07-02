import cv2
import numpy as np

# Receipts are rarely rotated more than this in practice; clamping avoids
# over-rotating near-square/noisy inputs where the minAreaRect angle is unstable.
_MAX_DESKEW_ANGLE_DEG = 15.0


class InvalidImageError(ValueError):
    """Raised when the input bytes cannot be decoded as an image."""


def decode_image(image_bytes: bytes) -> np.ndarray:
    array = np.frombuffer(image_bytes, dtype=np.uint8)
    image = cv2.imdecode(array, cv2.IMREAD_COLOR)
    if image is None:
        raise InvalidImageError("could not decode image bytes")
    return image


def _skew_angle(gray: np.ndarray) -> float:
    _, thresh = cv2.threshold(
        gray, 0, 255, cv2.THRESH_BINARY_INV | cv2.THRESH_OTSU
    )
    coords = cv2.findNonZero(thresh)
    if coords is None:
        return 0.0
    angle = cv2.minAreaRect(coords)[-1]
    # cv2.minAreaRect returns angle in (-90, 0]; normalize to a small
    # rotation around 0 rather than snapping to the nearest 90 degrees.
    if angle < -45:
        angle = 90 + angle
    return angle


def deskew(image: np.ndarray) -> np.ndarray:
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    angle = _skew_angle(gray)
    if abs(angle) < 0.1:
        return image
    angle = max(-_MAX_DESKEW_ANGLE_DEG, min(_MAX_DESKEW_ANGLE_DEG, angle))
    h, w = image.shape[:2]
    center = (w / 2, h / 2)
    matrix = cv2.getRotationMatrix2D(center, angle, 1.0)
    return cv2.warpAffine(
        image,
        matrix,
        (w, h),
        flags=cv2.INTER_CUBIC,
        borderMode=cv2.BORDER_REPLICATE,
    )


def enhance_contrast(image: np.ndarray) -> np.ndarray:
    gray = (
        cv2.cvtColor(image, cv2.COLOR_BGR2GRAY) if image.ndim == 3 else image
    )
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    return clahe.apply(gray)


def preprocess(image_bytes: bytes) -> np.ndarray:
    """Decode -> deskew -> contrast-enhance. Returns a grayscale ndarray ready for OCR."""
    image = decode_image(image_bytes)
    rotated = deskew(image)
    return enhance_contrast(rotated)
