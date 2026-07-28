import asyncio
import contextvars
import logging
import os
import time
import uuid
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import httpx
from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from ocr_api.auth import verify_ocr_secret
from ocr_api.insight_curator import (
    CurateInsightsRequest,
    CurateInsightsResponse,
    template_fallback,
)
from ocr_api.insights.graph import run_insight_graph
from ocr_api.models import OcrLine, OcrResponse, OcrWord
from ocr_api.ocr_engine import (
    _token_level_confidence_enabled,
    run_ocr_detailed,
    word_enrichment_threshold,
)
from ocr_api.preprocessing import InvalidImageError, preprocess
from ocr_api.receipt_understanding import (
    ReceiptUnderstandingError,
    ReceiptUnderstandingRequest,
    ReceiptUnderstandingResponse,
    call_receipt_understanding,
)

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


@asynccontextmanager
async def _lifespan(app: FastAPI) -> AsyncIterator[None]:
    # One pooled client for the process, not one per /understand call — the
    # LLM gateway is a separate host from Tesseract, so this is the only
    # outbound HTTP client this service makes.
    app.state.http_client = httpx.AsyncClient()
    try:
        yield
    finally:
        await app.state.http_client.aclose()


app = FastAPI(title="Receipt Drop OCR API", lifespan=_lifespan)
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


_RECEIPT_UNDERSTANDING_STATUS = {
    "server_misconfigured": 500,
    "llm_timeout": 504,
}


@app.exception_handler(ReceiptUnderstandingError)
async def receipt_understanding_error_handler(
    _: Request, exc: ReceiptUnderstandingError
) -> JSONResponse:
    # Every other code (llm_fetch_failed, llm_http_*, llm_invalid_response_json,
    # llm_unparseable_content) is an upstream (LLM gateway) failure -> 502.
    status_code = _RECEIPT_UNDERSTANDING_STATUS.get(exc.code, 502)
    return JSONResponse(status_code=status_code, content={"error": exc.code})


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post(
    "/ocr",
    response_model=OcrResponse,
    dependencies=[Depends(verify_ocr_secret)],
)
async def ocr(request: Request) -> OcrResponse:
    """Runs Tesseract OCR on the posted image, then — in the same request —
    the LLM receipt-understanding step (see ocr_api/receipt_understanding.py) on
    whatever text OCR found. The response already contains an interpreted
    receipt (`understanding`), not just raw text: this is the single
    synchronous OCR+LLM pipeline, not a two-stage capture-then-enrich flow.
    """
    start = time.perf_counter()
    body = await request.body()
    if not body:
        logger.warning("rejected: empty request body")
        raise HTTPException(status_code=400, detail="empty_body")

    logger.info("received receipt image (%.1f KB)", len(body) / 1024)

    try:
        processed = await asyncio.to_thread(preprocess, body)
    except InvalidImageError:
        logger.warning(
            "rejected: could not decode %d bytes (%.1f KB) as an image",
            len(body),
            len(body) / 1024,
        )
        raise HTTPException(status_code=400, detail="invalid_image")

    try:
        result = await asyncio.to_thread(run_ocr_detailed, processed)
    except Exception:
        logger.exception(
            "OCR processing failed after %.2fs", time.perf_counter() - start
        )
        raise HTTPException(status_code=500, detail="processing_failed")

    lines = result.lines
    confidence = result.confidence
    text = "\n".join(line.text for line in lines)
    elapsed = time.perf_counter() - start
    logger.info(
        "done in %.2fs: %d chars across %d lines, confidence %.0f%% (%s)%s",
        elapsed,
        len(text),
        len(lines),
        confidence * 100,
        _confidence_label(confidence),
        (
            f", adaptive bucket={result.strategy_bucket} psm={result.strategy_psm} "
            f"passes={result.pass_count} composite="
            f"{result.composite_score if result.composite_score is not None else 'n/a'}"
            if result.strategy_bucket is not None
            else ""
        ),
    )
    if text:
        logger.info("extracted text:\n%s", text)
        # This response body (text/lines) is what the client persists as
        # transactions.raw_ocr_text/ocr_header_text — log the per-line
        # breakdown at DEBUG so a bad LLM extraction (below) can be traced
        # back to what OCR actually saw (e.g. a merchant header line OCR
        # split across two lines, or a height_ratio too low for the
        # large-text merchant-candidate heuristic to have caught it either).
        if logger.isEnabledFor(logging.DEBUG):
            for i, line in enumerate(lines):
                logger.debug(
                    "  line %2d (height_ratio=%.2f): %r",
                    i,
                    line.height_ratio,
                    line.text,
                )
    else:
        logger.warning("no text recognized in the image")

    # LLM receipt understanding runs synchronously, in the same request, right
    # after OCR — the whole point of merging these two steps is that the
    # client gets an already-interpreted receipt back from one call, not raw
    # text it has to wait on a later async enrichment step to make sense of.
    # A failed/timed-out LLM call must never fail this response: OCR already
    # succeeded and its output is usable on its own.
    understanding = None
    understanding_error = None
    if text.strip():
        try:
            understanding = await call_receipt_understanding(
                text, http_client=request.app.state.http_client, lines=lines
            )
        except ReceiptUnderstandingError as exc:
            logger.warning(
                "LLM understanding failed for this /ocr call (%s) — "
                "returning raw OCR only",
                exc.code,
            )
            understanding_error = exc.code

    return OcrResponse(
        text=text,
        confidence=confidence,
        lines=[_public_ocr_line(line) for line in lines],
        understanding=understanding,
        understanding_error=understanding_error,
        strategy_psm=result.strategy_psm,
        strategy_bucket=result.strategy_bucket,
        pass_count=result.pass_count,
        composite_score=result.composite_score,
    )


def _public_ocr_line(line) -> OcrLine:
    """Map an internal OcrLineResult to the public OcrLine contract.

    When TOKEN_LEVEL_CONFIDENCE is off, confidence/words stay None so the
    response shape matches the pre-feature payload for older clients.
    When on: always include line confidence; attach words only below the
    enrichment threshold.
    """
    if not _token_level_confidence_enabled():
        return OcrLine(
            text=line.text,
            height_ratio=line.height_ratio,
            left_ratio=line.left_ratio,
            top_ratio=line.top_ratio,
            width_ratio=line.width_ratio,
        )
    enrich_words = line.confidence < word_enrichment_threshold()
    return OcrLine(
        text=line.text,
        height_ratio=line.height_ratio,
        left_ratio=line.left_ratio,
        top_ratio=line.top_ratio,
        width_ratio=line.width_ratio,
        confidence=line.confidence,
        words=(
            [
                OcrWord(
                    text=w.text,
                    confidence=w.confidence,
                    digit_corrected=w.digit_corrected,
                    left_ratio=w.left_ratio,
                    width_ratio=w.width_ratio,
                )
                for w in line.words
            ]
            if enrich_words and line.words
            else None
        ),
    )


@app.post(
    "/understand",
    response_model=ReceiptUnderstandingResponse,
    dependencies=[Depends(verify_ocr_secret)],
)
async def understand(
    request: Request, body: ReceiptUnderstandingRequest
) -> ReceiptUnderstandingResponse:
    """LLM receipt-understanding step: raw OCR text in, structured merchant
    info out (see ocr_api/receipt_understanding.py). No longer the primary path —
    POST /ocr now runs this same step synchronously right after Tesseract, so
    a client's own /ocr call already gets an interpreted receipt back in one
    round trip. This endpoint survives as: (a) enrich-transaction's fallback
    for rows that reached it without a usable precomputed understanding
    (legacy app version, or the client-side call above failed), and (b) a
    manual entry point for reprocessing previously-stored raw_ocr_text.

    No fallback: any failure here (timeout, LLM gateway down, unparseable
    response) propagates as an error response (see
    receipt_understanding_error_handler) rather than degrading to a weaker
    heuristic — this is a deliberate testing-phase decision, see
    docs/decisions.md.
    """
    if not body.ocr_text.strip():
        raise HTTPException(status_code=400, detail="empty_ocr_text")
    return await call_receipt_understanding(
        body.ocr_text, http_client=request.app.state.http_client
    )


@app.post(
    "/curate-insights",
    response_model=CurateInsightsResponse,
    dependencies=[Depends(verify_ocr_secret)],
)
async def curate_insights(
    request: Request, body: CurateInsightsRequest
) -> CurateInsightsResponse:
    """Rewrite a small structured insight-candidate pool into 1-3 friendly
    sentences via the LangGraph curation workflow (insight_router → optional
    specialists → Critic). Soft-degrades to template strings when the LLM is
    unavailable (unlike /understand's no-fallback testing-phase stance —
    insights must never fail loudly for the user)."""
    use_llm = os.environ.get("INSIGHTS_CURATOR_LLM", "1") == "1"
    use_specialists = os.environ.get("INSIGHTS_SPECIALIST_AGENTS_ENABLED", "0") == "1"
    engagement_weights = None
    if body.dismiss_counts:
        from ocr_api.insights.adaptive_routing import (
            engagement_weights_from_dismiss_counts,
        )

        engagement_weights = engagement_weights_from_dismiss_counts(body.dismiss_counts)
    try:
        return await run_insight_graph(
            body.candidates,
            http_client=request.app.state.http_client,
            use_llm=use_llm,
            use_specialists=use_specialists,
            engagement_weights=engagement_weights,
            dismissed_fact_keys=body.dismissed_fact_keys,
            dismiss_counts=body.dismiss_counts,
        )
    except ReceiptUnderstandingError:
        logger.exception("insight curator LLM failed — template fallback")
        from ocr_api.insights.prefilter import prefilter_candidates

        filtered = prefilter_candidates(
            [c for c in body.candidates if c.type and c.fact_key][:20],
            dismissed_fact_keys=body.dismissed_fact_keys,
            dismiss_counts=body.dismiss_counts,
        )
        return template_fallback(filtered)
    except Exception:
        # Graph/langgraph plumbing failure must never take down the request
        # as a 500 for the user — soft-degrade like a curator timeout.
        logger.exception("insight graph failed — template fallback")
        from ocr_api.insights.prefilter import prefilter_candidates

        filtered = prefilter_candidates(
            [c for c in body.candidates if c.type and c.fact_key][:20],
            dismissed_fact_keys=body.dismissed_fact_keys,
            dismiss_counts=body.dismiss_counts,
        )
        return template_fallback(filtered)
