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

# Tesseract's LSTM engine (--oem 3, the default per ocr_engine.py's _config())
# uses OpenMP internally and by default sizes its thread pool off the *node's*
# visible CPU count, not the container's cgroup quota — a well-known
# Kubernetes/OpenMP footgun. With deploy/k8s/ocr-api.yaml capping this
# container at 1 CPU, an oversubscribed thread pool gets repeatedly throttled
# by the kernel's CFS bandwidth controller mid-computation, inflating wall
# clock well beyond a properly single-threaded run. OMP_THREAD_LIMIT is the
# Tesseract-specific variable it checks directly; OMP_NUM_THREADS is set too
# as defense-in-depth for the underlying OpenMP runtime.
ENV OMP_THREAD_LIMIT=1
ENV OMP_NUM_THREADS=1

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
