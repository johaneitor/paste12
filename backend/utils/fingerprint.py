import os, hashlib
from flask import request, has_request_context

def client_fingerprint() -> str:
    """
    Huella estable por cliente: IP reenviada + User-Agent + SALT opcional.
    Corta a 32 chars para ahorrar.
    """
    if not has_request_context():
        return "noctx"
    ip = request.headers.get("X-Forwarded-For", "") or request.headers.get("CF-Connecting-IP", "") or request.remote_addr or ""
    ua = request.headers.get("User-Agent", "")
    salt = os.environ.get("FP_SALT", "")
    raw = f"{ip}|{ua}|{salt}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:32]
