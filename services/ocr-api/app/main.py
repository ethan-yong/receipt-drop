import contextvars
import logging
import os
import time
import uuid

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.auth import verify_ocr_secret
from app.models import OcrLine, OcrResponse
from app.ocr_engine import run_ocr_detailed
from app.preprocessing import InvalidImageError, preprocess

# Short id correlating every log line produced while handling one request.
# Without this, concurrent requests interleave in the log with no way to
# tell which "deskew"/"tesseract[plain]" line belongs to which /ocr call.
_request_id: contextvars.ContextVar[str] = contextvars.ContextVar(
    "ocr_request_id", default="-"
)


class _RequestIdFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        record.request_id = _request_id.get()
        return True


logging.basicConfig(
    level=os.environ.get("OCR_LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s [%(request_id)s] %(name)s: %(message)s",
)
for _handler in logging.getLogger().handlers:
    _handler.addFilter(_RequestIdFilter())

logger = logging.getLogger("ocr_api.main")

app = FastAPI(title="Receipt Drop OCR API")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def _assign_request_id(request: Request, call_next):
    token = _request_id.set(uuid.uuid4().hex[:8])
    try:
        return await call_next(request)
    finally:
        _request_id.reset(token)


def _confidence_label(confidence: float) -> str:
    """Rough human-facing quality label for the log summary only — the Dart
    client applies its own thresholds downstream; this isn't relied on by
    anything, it just makes the log skimmable at a glance."""
    if confidence >= 0.7:
        return "good"
    if confidence >= 0.4:
        return "fair"
    return "poor"


@app.exception_handler(HTTPException)
async def http_exception_handler(_: Request, exc: HTTPException) -> JSONResponse:
    return JSONResponse(status_code=exc.status_code, content={"error": exc.detail})


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post(
    "/ocr",
    response_model=OcrResponse,
    dependencies=[Depends(verify_ocr_secret)],
)
async def ocr(request: Request) -> OcrResponse:
    start = time.perf_counter()
    body = await request.body()
    if not body:
        logger.warning("rejected: empty request body")
        raise HTTPException(status_code=400, detail="empty_body")

    logger.info("received receipt image (%.1f KB)", len(body) / 1024)

    try:
        processed = preprocess(body)
    except InvalidImageError:
        logger.warning(
            "rejected: could not decode %d bytes (%.1f KB) as an image",
            len(body),
            len(body) / 1024,
        )
        raise HTTPException(status_code=400, detail="invalid_image")

    try:
        lines, confidence = run_ocr_detailed(processed)
    except Exception:
        logger.exception(
            "OCR processing failed after %.2fs", time.perf_counter() - start
        )
        raise HTTPException(status_code=500, detail="processing_failed")

    text = "\n".join(line.text for line in lines)
    elapsed = time.perf_counter() - start
    logger.info(
        "done in %.2fs: %d chars across %d lines, confidence %.0f%% (%s)",
        elapsed,
        len(text),
        len(lines),
        confidence * 100,
        _confidence_label(confidence),
    )
    if text:
        logger.info("extracted text:\n%s", text)
    else:
        logger.warning("no text recognized in the image")
    return OcrResponse(
        text=text,
        confidence=confidence,
        lines=[
            OcrLine(text=line.text, height_ratio=line.height_ratio) for line in lines
        ],
    )
