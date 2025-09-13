
from sqlalchemy import text as _text

def _json(code, payload):
    """(status, headers, body) JSON estándar, no-store, idempotente"""
    body = _json_mod.dumps(payload, default=str).encode("utf-8")
    status = f"{code} OK"
    headers = [
        ("Content-Type", "application/json; charset=utf-8"),
        ("Content-Length", str(len(body))),
        ("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0"),
        ("X-WSGI-Bridge", "1"),
    ]
    return status, headers, body



T = _text
import os, sys, json, mimetypes, hashlib
from importlib import import_module
from typing import Callable, Tuple
from datetime import datetime, timedelta, timezone

def _inject_single_meta(body_bytes):
    try:
        b = body_bytes if isinstance(body_bytes, (bytes, bytearray)) else (body_bytes or b"")
        if not b:
            return body_bytes
        if (b.find(b'data-single="1"') != -1) and (b.find(b'name="p12-single"') == -1):
            return b.replace(b"<head", b"<head><meta name=\"p12-single\" content=\"1\">", 1)
    except Exception:
        pass
    return body_bytes

_THIS = os.path.abspath(__file__)
_REPO_DIR = os.path.dirname(os.path.dirname(_THIS))
if _REPO_DIR not in sys.path:
    sys.path.insert(0, _REPO_DIR)

CANDIDATES = ["app:app", "run:app", "render_entry:app", "entry_main:app"]

def _resolve_app():
    last_err = None
    for spec in CANDIDATES:
        try:
            os.environ["APP_MODULE"] = spec
            sys.modules.pop("patched_app", None)
            pa = import_module("patched_app")
            return getattr(pa, "app")
        except Exception as e:
            last_err = e
    print(f"[wsgiapp] WARNING: no pude resolver APP_MODULE (probados {CANDIDATES}). Último error: {last_err!r}")
    return None

def _bootstrap_db():
    from sqlalchemy import create_engine, text
    url = os.environ.get("DATABASE_URL", "") or os.environ.get("SQLALCHEMY_DATABASE_URI","")
    if not url:
        return
    eng = create_engine(url, pool_pre_ping=True)
    with eng.begin() as cx:
        cx.execute(text("""
            CREATE TABLE IF NOT EXISTS note(
                id SERIAL PRIMARY KEY,
                title TEXT, url TEXT, summary TEXT, content TEXT,
                text TEXT,
                timestamp TIMESTAMPTZ DEFAULT NOW(),
                expires_at TIMESTAMPTZ,
                likes INT DEFAULT 0,
                views INT DEFAULT 0,
                reports INT DEFAULT 0,
                author_fp VARCHAR(64)
            )
        """))
        cx.execute(text("""
            CREATE TABLE IF NOT EXISTS report_log(
                id SERIAL PRIMARY KEY,
                note_id INT NOT NULL,
                fingerprint VARCHAR(128) NOT NULL,
                created_at TIMESTAMPTZ DEFAULT NOW()
            )
        """))
        cx.execute(text("""
            CREATE TABLE IF NOT EXISTS like_log(
                id SERIAL PRIMARY KEY,
                note_id INT NOT NULL,
                fingerprint VARCHAR(128) NOT NULL,
                created_at TIMESTAMPTZ DEFAULT NOW()
            )
        """))
        # índices (pueden ya existir)
        try: cx.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS uq_report_note_fp ON report_log (note_id, fingerprint)"))
        except Exception: pass
        try: cx.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS uq_like_note_fp ON like_log (note_id, fingerprint)"))
        except Exception: pass
_bootstrap_db()

def _json(status: int, data: dict) -> Tuple[str, list, bytes]:
    body = json.dumps(data, default=str).encode("utf-8")
    status_line = f"{status} " + ("OK" if status == 200 else "ERROR")
    headers = [("Content-Type", "application/json; charset=utf-8"),
               ("Content-Length", str(len(body)))]
    return status_line, headers, body

def _html(status: int, body_html: str, ctype="text/html; charset=utf-8"):
    body = body_html.encode("utf-8")
    status_line = f"{status} " + ("OK" if status == 200 else "ERROR")
    headers = [("Content-Type", ctype), ("Content-Length", str(len(body)))]
    return status_line, headers, body

def _finish(start_response, status, headers, body, method, extra_headers=None):
    try:
        # Normaliza body a bytes
        if isinstance(body, (bytes, bytearray)):
            body_bytes = bytes(body)
        elif body is None:
            body_bytes = b""
        elif isinstance(body, list):
            body_bytes = b"".join(x if isinstance(x,(bytes,bytearray)) else str(x).encode("utf-8") for x in body)
        elif isinstance(body, str):
            body_bytes = body.encode("utf-8")
        else:
            try:
                body_bytes = bytes(body)
            except Exception:
                body_bytes = str(body).encode("utf-8")

        # Inyecta meta p12-single si detecta body data-single
        try:
            body_bytes = _inject_single_meta(body_bytes)
        except Exception:
            pass

        # Unifica headers + extra y asegura Content-Length
        hdrs = list(headers or [])
        if extra_headers:
            hdrs.extend(list(extra_headers))
        if not any((k.lower() == "content-length") for k,_ in hdrs):
            hdrs.append(("Content-Length", str(len(body_bytes))))
        has_ct = None
        for k,v in hdrs:
            if k.lower() == "content-type":
                has_ct = v; break
        if has_ct is None and (body_bytes.startswith(b"<!doctype html") or b"<html" in body_bytes[:200]):
            hdrs.append(("Content-Type","text/html; charset=utf-8"))

        start_response(status, hdrs)
        return [body_bytes]
    except Exception:
        try:
            start_response("500 Internal Server Error", [("Content-Type","text/plain; charset=utf-8")])
        except Exception:
            pass
        return [b"internal error"]