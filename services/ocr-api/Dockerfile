FROM python:3.11-slim

WORKDIR /app

# USE_TESSDATA_BEST=1 downloads the higher-accuracy LSTM models (~94 MB each)
# from the tessdata_best repository. Default is 0 (uses the standard apt
# models, faster CI builds). Set to 1 for production images only.
#
# When USE_TESSDATA_BEST=1, also pass --build-arg TESSDATA_DIR=/tessdata so
# Tesseract finds the downloaded models at runtime:
#   docker build --build-arg USE_TESSDATA_BEST=1 --build-arg TESSDATA_DIR=/tessdata .
ARG USE_TESSDATA_BEST=0
ARG TESSDATA_DIR=""
ENV TESSDATA_PREFIX=$TESSDATA_DIR

# eng traineddata ships with tesseract-ocr; msa adds Malay for local receipts.
# wget/ca-certificates only needed when USE_TESSDATA_BEST=1 but kept for the
# conditional; they add ~4 MB to the layer.
RUN apt-get update && apt-get install -y --no-install-recommends \
    tesseract-ocr tesseract-ocr-msa wget ca-certificates \
    && if [ "$USE_TESSDATA_BEST" = "1" ]; then \
         mkdir -p /tessdata \
         && wget -q -O /tessdata/eng.traineddata \
              https://github.com/tesseract-ocr/tessdata_best/raw/main/eng.traineddata \
         && wget -q -O /tessdata/msa.traineddata \
              https://github.com/tesseract-ocr/tessdata_best/raw/main/msa.traineddata; \
       fi \
    && rm -rf /var/lib/apt/lists/*

COPY pyproject.toml .
COPY ocr_api ./ocr_api
RUN pip install --no-cache-dir .

EXPOSE 8080
CMD ["uvicorn", "ocr_api.main:app", "--host", "0.0.0.0", "--port", "8080"]
