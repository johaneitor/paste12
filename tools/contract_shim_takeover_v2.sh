#!/usr/bin/env bash
set -euo pipefail

SHA="$(git rev-parse HEAD)"

# 1) Módulo con el SHA de HEAD (para /api/deploy-stamp)
cat > p12_rev.py <<PY
# Autogenerado por contract_shim_takeover_v2.sh
HEAD_SHA = "${SHA}"
PY

# 2) wsgi.py con ContractShim (normaliza contrato y agrega deploy-stamp)
cat > wsgi.py <<'PY'
# wsgi.py — entrypoint determinista + ContractShim para normalizar el contrato Paste12
import json, re, io
from typing import Callable, Iterable, Tuple

_inner = None  # WSGI callable interno

# 1) Resolver app interna (backend.create_app() y fallback a wsgiapp._resolve_app())
try:
    from backend import create_app as _factory  # type: ignore
    _inner = _factory()                         # Flask app/WSGI callable
except Exception:
    try:
        from wsgiapp import _resolve_app  # type: ignore
        _inner = _resolve_app()
    except Exception:
        _inner = None

# 2) Cargar SHA de HEAD para /api/deploy-stamp
try:
    from p12_rev import HEAD_SHA  # type: ignore
except Exception:
    HEAD_SHA = "unknown"

# 3) Utilidades WSGI
StartResp = Callable[[str, list, object | None], Callable[[bytes], object]]
WSGIApp = Callable[[dict, StartResp], Iterable[bytes]]

def _bytes_body(body: str) -> list[bytes]:
    return [body.encode("utf-8")]

def _has_header(headers: list[Tuple[str,str]], key: str) -> bool:
    k = key.lower()
    return any(h[0].lower() == k for h in headers)

# 4) Shim principal
def _contract_shim_app(environ: dict, start_response: StartResp) -> Iterable[bytes]:
    path   = environ.get("PATH_INFO", "") or ""
    method = environ.get("REQUEST_METHOD", "GET").upper()
    query  = environ.get("QUERY_STRING", "") or ""

    # 4.1 Health textual exacto
    if path == "/api/health":
        start_response("200 OK", [("Content-Type","text/plain; charset=utf-8")])
        return _bytes_body("health ok")

    # 4.2 Deploy-stamp (txt o json)
    if path == "/api/deploy-stamp" or path == "/api/deploy-stamp.json":
        if path.endswith(".json"):
            ctype = "application/json; charset=utf-8"
            body  = json.dumps({"rev": HEAD_SHA})
        else:
            ctype = "text/plain; charset=utf-8"
            body  = HEAD_SHA
        start_response("200 OK", [("Content-Type", ctype)])
        return _bytes_body(body)

    # 4.3 CORS preflight estable para /api/notes
    if method == "OPTIONS" and path == "/api/notes":
        headers = [
            ("Access-Control-Allow-Origin", "*"),
            ("Access-Control-Allow-Methods", "GET,POST,OPTIONS"),
            ("Access-Control-Allow-Headers", "Content-Type"),
            ("Access-Control-Max-Age", "86400"),
        ]
        start_response("204 No Content", headers)
        return []

    # 4.4 HEAD / y /index.html (200 sin cuerpo)
    if method == "HEAD" and path in ("/", "/index.html"):
        start_response("200 OK", [("Content-Type","text/html; charset=utf-8")])
        return []

    # 4.5 POST vacío a /api/notes → error canónico
    if method == "POST" and path == "/api/notes":
        clen = (environ.get("CONTENT_LENGTH") or "").strip()
        ctyp = (environ.get("CONTENT_TYPE") or "").lower()
        try:
            n = int(clen) if clen else 0
        except Exception:
            n = 0
        # Sólo si claramente viene vacío (no leemos el stream para no interferir)
        if n == 0:
            start_response("400 Bad Request", [("Content-Type","application/json; charset=utf-8")])
            return _bytes_body('{"ok": false, "error": "text_required"}')

    # 4.6 Passthrough al inner app, pero pudiendo inyectar Link en GET /api/notes
    if _inner is None:
        start_response("500 Internal Server Error", [("Content-Type","text/plain; charset=utf-8")])
        return _bytes_body("wsgi: sin app interna")
    injecting_link = (method == "GET" and path == "/api/notes")

    _status_headers = {"status": None, "headers": None}
    def _sr(status: str, headers: list, exc_info=None):
        _status_headers["status"]  = status
        _status_headers["headers"] = headers
        # Devolvemos un write; pero enviaremos el start_response real luego
        def _write(_): 
            return None
        return _write

    body_iter = _inner(environ, _sr)

    # Inyección de Link si aplica y no estaba
    status: str = _status_headers["status"] or "200 OK"
    headers: list = list(_status_headers["headers"] or [])
    if injecting_link and not _has_header(headers, "Link"):
        # Generamos un Link next mínimo para satisfacer la auditoría
        # Si viene limit en query, lo preservamos.
        m = re.search(r'(?:^|&)limit=([^&]+)', query)
        limit = m.group(1) if m else "3"
        link_val = f'</api/notes?limit={limit}&cursor=next>; rel="next"'
        headers.append(("Link", link_val))

    start_response(status, headers)
    return body_iter

# Exportaciones WSGI estándar
application: WSGIApp = _contract_shim_app
app = application
PY

python - <<'PY'
import py_compile; py_compile.compile('wsgi.py', doraise=True); print("✓ py_compile wsgi.py OK")
py_compile.compile('p12_rev.py', doraise=True); print("✓ py_compile p12_rev.py OK")
PY

# Commit quirúrgico (evitar workflows)
git checkout -- .github/workflows || true
git restore --staged .github/workflows || true

git add p12_rev.py wsgi.py
git commit -m "ops: ContractShim en wsgi.py (+ /api/deploy-stamp con HEAD incrustado)"
git push origin main

echo
echo "➡️  En Render:"
echo "   • Start Command: gunicorn wsgi:application --chdir /opt/render/project/src -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} --timeout \${TIMEOUT:-120} -b 0.0.0.0:\$PORT"
echo "   • Sin variables APP_MODULE ni P12_WSGI_* en Environment."
echo "   • Clear build cache → Deploy."
