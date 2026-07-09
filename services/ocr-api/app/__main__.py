"""Local dev server: ``uv run ocr-api`` from repo root, or ``python -m app`` here."""

from __future__ import annotations

import os
import socket
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


def _port_in_use(host: str, port: int) -> bool:
    # Windows lets a second process bind an already-listening port silently
    # (SO_REUSEADDR semantics differ from Linux), so a bind-test can't detect
    # a stale leftover instance — a real connect attempt can. 0.0.0.0/:: mean
    # "all interfaces", which isn't itself connectable, so probe loopback.
    probe_host = "127.0.0.1" if host in ("0.0.0.0", "", "::") else host
    try:
        with socket.create_connection((probe_host, port), timeout=0.5):
            return True
    except OSError:
        return False


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

    host = os.environ.get("OCR_API_HOST", "0.0.0.0")
    port = int(os.environ.get("OCR_API_PORT", "8081"))

    # A leftover instance from an earlier terminal keeps answering requests
    # with its own (possibly stale) config, and a new instance on top of it
    # looks like it started fine — the confusing failure mode this guards
    # against. Killing the old one is the fix, not starting another.
    if _port_in_use(host, port):
        print(
            f"ERROR: something is already listening on port {port}.\n"
            "That's usually a leftover instance from an earlier terminal —\n"
            "with reload mode on, its worker child survives even after you\n"
            "stop what looked like the main process. Stop the whole tree:\n"
            f"  .\\scripts\\stop_ocr_api.ps1 -Port {port}\n"
            "or, next time, prefer Ctrl+C in the terminal it's running in\n"
            "(not closing the window) so reload can shut down cleanly.",
            file=sys.stderr,
        )
        sys.exit(1)

    import uvicorn

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
