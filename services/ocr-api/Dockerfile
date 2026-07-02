FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

COPY pyproject.toml .
COPY app ./app
RUN pip install --no-cache-dir .

# Pre-warm PaddleOCR model weights at build time so a Cloud Run cold start
# only pays inference cost, not model-download cost.
RUN python -c "from app.ocr_engine import get_engine; get_engine()"

EXPOSE 8080
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
