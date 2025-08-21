import os, hashlib
from flask import request, has_request_context

def client_fingerprint() -> str:
    if not has_request_context():
        return "noctx"
    ip = request.headers.get("X-Forwarded-For", "") or request.headers.get("CF-Connecting-IP", "") or (request.remote_addr or "")
    ua = request.headers.get("User-Agent", "")
    salt = os.environ.get("FP_SALT", "")
    return hashlib.sha256(f"{ip}|{ua}|{salt}".encode()).hexdigest()[:32]
