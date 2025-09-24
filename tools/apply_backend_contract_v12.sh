#!/usr/bin/env bash
set -euo pipefail
echo "== apply_backend_contract_v12 =="

# --- contract_shim.py ---
cat > contract_shim.py <<'PY'
# -*- coding: utf-8 -*-
"""
Paste12 Contract Shim v12
- OPTIONS /api/notes -> 204 + CORS (ACAO/ACAM/ACAH/Max-Age)
- Forzar CORS también en GET/POST /api/notes
- Link: <...>; rel="next" en GET /api/notes si hay página siguiente
- FORM→JSON shim en POST /api/notes (acepta application/x-www-form-urlencoded con 'text=')
- Exporta 'application' WSGI
"""
import io, json, urllib.parse, re
from typing import Callable, Iterable, Tuple

Headers = list[tuple[str, str]]
StartResp = Callable[[str, Headers,], Callable[[bytes], None]]

def _import_real_app():
    # Intentos comunes
    candidates = [
        ("wsgiapp", "application"),
        ("wsgiapp", "app"),
        ("app", "application"),
        ("app", "app"),
    ]
    for mod, attr in candidates:
        try:
            m = __import__(mod, fromlist=[attr])
            return getattr(m, attr)
        except Exception:
            pass
    # Fallback de error visible
    def _err_app(environ, start_response):
        start_response("500 Internal Server Error", [("Content-Type","text/plain; charset=utf-8")])
        return [b"paste12: real application not found by contract_shim"]
    return _err_app

REAL_APP = _import_real_app()

def _get_qs(environ) -> dict[str, list[str]]:
    return urllib.parse.parse_qs(environ.get("QUERY_STRING",""), keep_blank_values=True)

def _get_limit(environ, default:int=10) -> int:
    try:
        qs = _get_qs(environ)
        if "limit" in qs and qs["limit"]:
            return max(1, int(qs["limit"][0]))
    except Exception:
        pass
    return default

def _is_api_notes(environ) -> bool:
    return environ.get("PATH_INFO","") == "/api/notes"

def _add_cors(headers: Headers) -> Headers:
    # Añadimos/forzamos CORS mínimos
    wanted = {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "OPTIONS, GET, POST, HEAD",
        "Access-Control-Allow-Headers": "Content-Type",
        "Access-Control-Max-Age": "86400",
    }
    lower = {k.lower(): i for i,(k,_) in enumerate(headers)}
    for k,v in wanted.items():
        idx = lower.get(k.lower())
        if idx is None:
            headers.append((k,v))
        else:
            headers[idx] = (k,v)
    return headers

def _iter_capture_app(app, environ, start_response):
    # Helper para capturar status/headers/body del app real
    captured = {"status": None, "headers": None, "chunks": []}
    def sr(status, headers, exc_info=None):
        captured["status"] = status
        captured["headers"] = list(headers)
        def write(body):
            captured["chunks"].append(body)
        return write
    result = app(environ, sr)
    try:
        for chunk in result:
            captured["chunks"].append(chunk)
    finally:
        if hasattr(result, "close"):
            try: result.close()
            except Exception: pass
    return captured

def _json_load_maybe(b: bytes):
    try:
        return json.loads(b.decode("utf-8", errors="replace"))
    except Exception:
        return None

class P12Middleware:
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response: StartResp):
        path = environ.get("PATH_INFO","")
        method = environ.get("REQUEST_METHOD","GET").upper()

        # 1) Preflight OPTIONS /api/notes -> 204 con CORS
        if _is_api_notes(environ) and method == "OPTIONS":
            headers: Headers = []
            headers = _add_cors(headers)
            start_response("204 No Content", headers)
            return [b""]

        # 2) FORM→JSON shim en POST /api/notes
        if _is_api_notes(environ) and method == "POST":
            ctype = environ.get("CONTENT_TYPE","")
            if "application/x-www-form-urlencoded" in ctype:
                try:
                    length = int(environ.get("CONTENT_LENGTH","0") or "0")
                except Exception:
                    length = 0
                raw = environ["wsgi.input"].read(length) if length>0 else b""
                params = urllib.parse.parse_qs(raw.decode("utf-8", errors="replace"), keep_blank_values=True)
                text = (params.get("text") or [""])[0]
                # Reinyectar como JSON si no hay JSON válido
                payload = json.dumps({"text": text}).encode("utf-8")
                environ["wsgi.input"] = io.BytesIO(payload)
                environ["CONTENT_LENGTH"] = str(len(payload))
                environ["CONTENT_TYPE"] = "application/json"

        # 3) Ejecutar app real y capturar salida
        cap = _iter_capture_app(self.app, environ, start_response=lambda s,h: None)
        status: str = cap["status"] or "500 Internal Server Error"
        headers: Headers = cap["headers"] or []
        body_chunks: list[bytes] = cap["chunks"]

        # 4) CORS en respuestas /api/notes
        if _is_api_notes(environ):
            headers = _add_cors(headers)

        # 5) Link rel=next en GET /api/notes si procede
        if _is_api_notes(environ) and method in ("GET","HEAD"):
            # ¿ya hay Link?
            if not any(k.lower()=="link" for k,_ in headers):
                # Intentamos calcular next a partir del JSON (body)
                try:
                    # Para GET, tenemos body; para HEAD, puede no haber (lo dejamos en None)
                    full = b"".join(body_chunks) if body_chunks else b""
                    data = _json_load_maybe(full) if full[:1] in (b"[", b"{") else None
                    if isinstance(data, list) and data:
                        limit = _get_limit(environ, default=10)
                        if len(data) >= min(limit, len(data)):
                            last = data[min(len(data), limit)-1]
                            last_id = last.get("id") if isinstance(last, dict) else None
                            if last_id is not None:
                                qs = _get_qs(environ)
                                qs["limit"] = [str(limit)]
                                qs["before_id"] = [str(last_id)]
                                query = urllib.parse.urlencode({k:v[0] for k,v in qs.items()})
                                # reconstruimos URL
                                scheme = environ.get("wsgi.url_scheme","https")
                                host = environ.get("HTTP_HOST") or environ.get("SERVER_NAME")
                                path = environ.get("PATH_INFO","/api/notes")
                                next_url = f"{scheme}://{host}{path}?{query}" if host else f"{path}?{query}"
                                headers.append(("Link", f'<{next_url}>; rel="next"'))
                                # Extra opcional:
                                headers.append(("X-Next-Cursor", str(last_id)))
                except Exception:
                    pass  # silencioso; no romper respuesta

        # 6) Responder
        write = start_response(status, headers)
        if method == "HEAD":
            return [b""]  # sin body
        if body_chunks:
            for c in body_chunks: write(c)
            return []
        return [b""]  # por si acaso

application = P12Middleware(REAL_APP)
PY

python -m py_compile contract_shim.py
echo "✓ contract_shim.py actualizado y compilado"

# --- wsgi.py ---
cat > wsgi.py <<'PY'
# Simple export: Gunicorn cargará "wsgi:application"
from contract_shim import application  # type: ignore

# Ejecución local (opcional)
if __name__ == "__main__":
    try:
        from waitress import serve
        serve(application, listen="0.0.0.0:8080")
    except Exception:
        from wsgiref.simple_server import make_server
        httpd = make_server("0.0.0.0", 8080, application)
        httpd.serve_forever()
PY

python -m py_compile wsgi.py
echo "✓ wsgi.py compilado"
echo "Listo. Aconsejado en Render (Start Command):"
echo "  gunicorn wsgi:application --chdir /opt/render/project/src -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} --timeout \${TIMEOUT:-120} -b 0.0.0.0:\$PORT"
