#!/usr/bin/env bash
set -euo pipefail

ts="$(date -u +%Y%m%d-%H%M%SZ)"
backup="contract_shim.py.bak.$ts"
[ -f contract_shim.py ] && cp -f contract_shim.py "$backup" || true

cat > contract_shim.py <<'PY'
# -*- coding: utf-8 -*-
"""
Paste12 backend contract shim v13:
- Preflight CORS: responde 204 en OPTIONS /api/* + CORS headers
- CORS headers en todas las respuestas /api/*
- POST FORM -> JSON en /api/notes
- Link: <...>; rel="next" en GET /api/notes
- Exporta `application` para gunicorn (wsgi:application)
"""
from io import BytesIO
import json, sys
from typing import Iterable, List, Tuple
from urllib.parse import parse_qs, urlencode

# ===== localizar app real =====
def _fail_app(msg: str):
    def _app(environ, start_response):
        start_response("500 Internal Server Error", [("Content-Type","text/plain; charset=utf-8")])
        return [("Paste12 backend shim start error: " + msg).encode("utf-8")]
    return _app

def _import_real_app():
    try:
        # export canónico
        from wsgiapp import application as _app
        return _app
    except Exception as e1:
        try:
            from wsgiapp import app as _app
            return _app
        except Exception as e2:
            try:
                from app import app as _app
                return _app
            except Exception as e3:
                return _fail_app(f"cannot import real app: {e1!r} | {e2!r} | {e3!r}")

_real_app = _import_real_app()

# ===== util =====
def _set_header(headers: List[Tuple[str,str]], name: str, value: str):
    lname = name.lower()
    out: List[Tuple[str,str]] = []
    replaced = False
    for k,v in headers:
        if k.lower() == lname:
            if not replaced:
                out.append((name, value))
                replaced = True
        else:
            out.append((k, v))
    if not replaced:
        out.append((name, value))
    return out

def _cors_headers(headers: List[Tuple[str,str]]):
    headers = _set_header(headers, "Access-Control-Allow-Origin",  "*")
    headers = _set_header(headers, "Access-Control-Allow-Methods", "GET, POST, HEAD, OPTIONS")
    headers = _set_header(headers, "Access-Control-Allow-Headers", "Content-Type")
    headers = _set_header(headers, "Access-Control-Max-Age",       "86400")
    return headers

def _wsgi_url(environ) -> str:
    scheme = environ.get("wsgi.url_scheme","http")
    host   = environ.get("HTTP_HOST") or environ.get("SERVER_NAME","localhost")
    path   = environ.get("PATH_INFO","/")
    qs     = environ.get("QUERY_STRING","")
    return f"{scheme}://{host}{path}" + (f"?{qs}" if qs else "")

# ===== middleware =====
def _shim_app(app):
    def _app(environ, start_response):
        method = (environ.get("REQUEST_METHOD") or "GET").upper()
        path   = environ.get("PATH_INFO") or "/"

        # 1) Preflight CORS en /api/*
        if method == "OPTIONS" and path.startswith("/api/"):
            h = []
            h = _cors_headers(h)
            start_response("204 No Content", h)
            return []

        # 2) Transformar POST FORM -> JSON en /api/notes
        if method == "POST" and path == "/api/notes":
            ctype = (environ.get("CONTENT_TYPE") or "").split(";",1)[0].strip().lower()
            if ctype in ("application/x-www-form-urlencoded","multipart/form-data"):
                try:
                    length = int(environ.get("CONTENT_LENGTH") or "0")
                except ValueError:
                    length = 0
                raw = environ.get("wsgi.input").read(length) if length > 0 else b""
                params = parse_qs(raw.decode("utf-8", "replace"), keep_blank_values=True)
                text = (params.get("text") or [""])[0]
                payload = json.dumps({"text": text}).encode("utf-8")
                environ["wsgi.input"]    = BytesIO(payload)
                environ["CONTENT_LENGTH"] = str(len(payload))
                environ["CONTENT_TYPE"]   = "application/json"

        captured = {"status": None, "headers": None, "exc": None}
        def _sr(status, headers, exc_info=None):
            # CORS para todas las respuestas /api/*
            if path.startswith("/api/"):
                headers = _cors_headers(list(headers))
            captured["status"]  = status
            captured["headers"] = headers
            captured["exc"]     = exc_info
            # devolvemos no-op write callable
            return lambda _b: None

        iterable = app(environ, _sr)
        body_chunks: List[bytes] = []
        try:
            for chunk in iterable:
                body_chunks.append(chunk)
        finally:
            if hasattr(iterable, "close"):
                try: iterable.close()
                except Exception: pass

        status  = captured["status"] or "200 OK"
        headers: List[Tuple[str,str]] = list(captured["headers"] or [])
        body = b"".join(body_chunks)

        # 3) Link rel=next en GET /api/notes (si 200 + JSON)
        if method == "GET" and path == "/api/notes" and status.startswith("200"):
            ctype_hdr = next((v for (k,v) in headers if k.lower()=="content-type"), "")
            if "application/json" in (ctype_hdr or ""):
                try:
                    data = json.loads(body.decode("utf-8"))
                except Exception:
                    data = []
                ids = []
                if isinstance(data, list):
                    for n in data:
                        if isinstance(n, dict) and "id" in n:
                            ids.append(n["id"])
                # construir next con before_id si hay ids; mantener otros qs (p.ej., limit)
                qs = parse_qs(environ.get("QUERY_STRING",""), keep_blank_values=True)
                flat_qs = {k: (v[-1] if v else "") for k,v in qs.items()}
                if ids:
                    flat_qs["before_id"] = str(min(ids))
                base = _wsgi_url({**environ, "QUERY_STRING": ""})
                next_qs = urlencode(flat_qs)
                next_url = base + (("?" + next_qs) if next_qs else "")
                headers = _set_header(headers, "Link", f'<{next_url}>; rel="next"')

        start_response(status, headers, captured["exc"])
        return [body]
    return _app

application = _shim_app(_real_app)
app = application  # alias opcional
PY

python - <<'PY'
import py_compile
py_compile.compile("contract_shim.py", doraise=True)
PY

echo "✓ contract_shim.py actualizado y compilado"
echo "→ Sugerido Start Command en Render:"
echo "  gunicorn wsgi:application --chdir /opt/render/project/src -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} --timeout \${TIMEOUT:-120} -b 0.0.0.0:\$PORT"
