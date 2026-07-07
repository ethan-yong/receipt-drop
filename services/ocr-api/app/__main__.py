"""Local dev server: ``uv run ocr-api`` from repo root, or ``python -m app`` here."""

from __future__ import annotations

import os
import sys
from pathlib import Path


def _repo_root() -> Path:
    # services/ocr-api/app/__main__.py → receipt-drop/
    return Path(__file__).resolve().parents[3]


def _load_root_dotenv() -> None:
    env_file = _repo_root() / ".env"
    if not env_file.is_file():
        return
    for raw in env_file.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


def _maybe_set_tesseract_cmd() -> None:
    if os.environ.get("TESSERACT_CMD"):
        return
    candidates = [
        Path(r"C:\Program Files\Tesseract-OCR\tesseract.exe"),
        Path(r"C:\Program Files (x86)\Tesseract-OCR\tesseract.exe"),
    ]
    for path in candidates:
        if path.is_file():
            os.environ["TESSERACT_CMD"] = str(path)
            return


def main() -> None:
    _load_root_dotenv()
    _maybe_set_tesseract_cmd()

    if not os.environ.get("OCR_SHARED_SECRET", "").strip():
        print(
            "ERROR: OCR_SHARED_SECRET is not set.\n"
            "Add it to .env at the repo root (see .env.example), then retry.",
            file=sys.stderr,
        )
        sys.exit(1)

    import uvicorn

    host = os.environ.get("OCR_API_HOST", "0.0.0.0")
    port = int(os.environ.get("OCR_API_PORT", "8081"))
    reload = os.environ.get("OCR_API_RELOAD", "true").lower() in ("1", "true", "yes")

    print(f"Starting OCR API on http://{host}:{port} (reload={reload})")
    uvicorn.run(
        "app.main:app",
        host=host,
        port=port,
        reload=reload,
    )


if __name__ == "__main__":
    main()
