# Start the self-hosted OCR API (Tesseract + OpenCV).
# From repo root:
#   uv sync
#   uv run ocr-api
#
# Loads OCR_SHARED_SECRET from .env at repo root. Default port: 8081
# (matches supabase/functions/.env.example).

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

Push-Location $ProjectRoot
try {
    uv run ocr-api @args
} finally {
    Pop-Location
}
