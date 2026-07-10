"""Local dev server: ``uv run ocr-api`` from repo root, or ``python -m app`` here."""

from __future__ import annotations

import os
import signal
import socket
import subprocess
import sys
import time
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


def _free_port(port: int) -> None:
    """Stop whatever is listening on *port* (including uvicorn --reload children)."""
    if sys.platform == "win32":
        script = _repo_root() / "scripts" / "stop_ocr_api.ps1"
        if script.is_file():
            subprocess.run(
                [
                    "powershell",
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    str(script),
                    "-Port",
                    str(port),
                ],
                check=False,
            )
            return
        # Fallback when the script isn't present (e.g. installed wheel only).
        result = subprocess.run(
            [
                "powershell",
                "-NoProfile",
                "-Command",
                (
                    f"Get-NetTCPConnection -LocalPort {port} -State Listen "
                    "-ErrorAction SilentlyContinue | "
                    "Select-Object -ExpandProperty OwningProcess -Unique | "
                    "ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue }"
                ),
            ],
            check=False,
        )
        if result.returncode != 0:
            print(
                f"WARNING: could not run port cleanup for {port} on Windows.",
                file=sys.stderr,
            )
        return

    # macOS / Linux dev: kill listeners reported by lsof, then fuser as fallback.
    for cmd in (
        ["lsof", "-ti", f":{port}"],
        ["fuser", f"{port}/tcp"],
    ):
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, check=False)
        except FileNotFoundError:
            continue
        if cmd[0] == "lsof" and result.stdout.strip():
            for pid_str in result.stdout.strip().split():
                try:
                    os.kill(int(pid_str), signal.SIGTERM)
                except (ProcessLookupError, ValueError):
                    pass
        elif cmd[0] == "fuser" and result.returncode == 0:
            subprocess.run(["fuser", "-k", f"{port}/tcp"], check=False)
        break


def _ensure_port_available(host: str, port: int) -> None:
    if not _port_in_use(host, port):
        return

    print(
        f"Port {port} is in use (leftover OCR API instance?) — stopping it...",
        file=sys.stderr,
    )
    _free_port(port)

    for _ in range(20):
        if not _port_in_use(host, port):
            print(f"Port {port} is clear.", file=sys.stderr)
            return
        time.sleep(0.25)

    print(
        f"ERROR: port {port} is still in use after cleanup.\n"
        f"Try manually: .\\scripts\\stop_ocr_api.ps1 -Port {port}",
        file=sys.stderr,
    )
    sys.exit(1)


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

    # A leftover instance (often a uvicorn --reload worker child) keeps
    # answering with stale config; free the port before we bind.
    _ensure_port_available(host, port)

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
