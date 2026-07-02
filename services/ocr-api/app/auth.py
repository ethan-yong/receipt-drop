import os
import secrets

from fastapi import Header, HTTPException


def verify_ocr_secret(x_ocr_secret: str | None = Header(default=None)) -> None:
    """This service is only ever called by the Supabase edge function proxy,
    never directly by a client, so a shared secret (not per-user JWT) is enough."""
    expected = os.environ.get("OCR_SHARED_SECRET", "").strip()
    if not expected:
        raise HTTPException(status_code=500, detail="server_misconfigured")
    if not x_ocr_secret or not secrets.compare_digest(x_ocr_secret, expected):
        raise HTTPException(status_code=401, detail="unauthorized")
