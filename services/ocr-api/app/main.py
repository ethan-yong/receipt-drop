from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.auth import verify_ocr_secret
from app.models import OcrResponse
from app.ocr_engine import run_ocr
from app.preprocessing import InvalidImageError, preprocess

app = FastAPI(title="Receipt Drop OCR API")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


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
    body = await request.body()
    if not body:
        raise HTTPException(status_code=400, detail="empty_body")

    try:
        processed = preprocess(body)
    except InvalidImageError:
        raise HTTPException(status_code=400, detail="invalid_image")

    try:
        text, confidence = run_ocr(processed)
    except Exception:
        raise HTTPException(status_code=500, detail="processing_failed")

    return OcrResponse(text=text, confidence=confidence)
