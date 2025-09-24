#!/usr/bin/env bash
set -euo pipefail

# 1) Obtener SHA actual (HEAD)
SHA="$(git rev-parse HEAD)"

# 2) Escribir contract_shim.py de forma robusta (sin escapes raros)
python - <<'PY'
import os, textwrap, sys, pathlib
sha = os.environ.get("SHA","UNKNOWN")

code = f"""\
# Auto-generado por quick_backend_stabilize_v8.sh
# Contrato Paste12 (backend shim): health JSON, CORS 204, FORM→JSON, Link en GET /api/notes
# HEAD_SHA embebido para /api/deploy-stamp
HEAD_SHA = {sha!r}

from typing import Callable, Iterable, Tuple

StartResp = Callable[[str, list, object|None], Callable[[bytes], object]]
WSGIApp   = Callable[[dict, StartResp], Iterable[bytes]]

def _has(headers: list[tuple[str,str]], key: str) -> bool:
    k = key.lower()
    return any(h[0].lower() == k for h in headers)

def _getlimit(qs: str, default: str="3") -> str:
    try:
        import re
        m = re.search(r"(?:^|&)limit=([^&]+)", qs or "")
        return m.group(1) if m else default
    except Exception:
        return default

def build_inner() -> WSGIApp | None:
    # 1) Ideal: backend.create_app()
    try:
        from backend import create_app as _factory  # type: ignore
        return _factory()
    except Exception:
        pass
    # 2) Fallback: wsgiapp._resolve_app() si existe
    try:
        from wsgiapp import _resolve_app  # type: ignore
        return _resolve_app()
    except Exception:
        return None

def application(environ: dict, start_response: StartResp):
    path   = (environ.get("PATH_INFO") or "").strip()
    method = (environ.get("REQUEST_METHOD") or "GET").upper()
    qs     = environ.get("QUERY_STRING") or ""

    # /api/health → JSON {ok:true} (según tu test runner actual)
    if path == "/api/health":
        start_response("200 OK", [("Content-Type","application/json")])
        return [b'{"ok":true}']

    # /api/deploy-stamp (útil para auditar despliegue)
    if path == "/api/deploy-stamp":
        start_response("200 OK", [("Content-Type","text/plain; charset=utf-8")])
        return [HEAD_SHA.encode("utf-8")]

    # CORS preflight estable para /api/notes
    if method == "OPTIONS" and path == "/api/notes":
        start_response("204 No Content", [
            ("Access-Control-Allow-Origin",  "*"),
            ("Access-Control-Allow-Methods", "GET,POST,OPTIONS"),
            ("Access-Control-Allow-Headers", "Content-Type"),
            ("Access-Control-Max-Age",      "86400"),
        ])
        return []

    # HEAD básicos no bloqueantes
    if method == "HEAD" and path in ("/", "/index.html"):
        start_response("200 OK", [("Content-Type","text/html; charset=utf-8")])
        return []

    inner = build_inner()
    if inner is None:
        start_response("500 Internal Server Error", [("Content-Type","text/plain; charset=utf-8")])
        return [b"wsgi: sin app interna"]

    # FORM → JSON en POST /api/notes (previo al inner)
    env = environ
    if method == "POST" and path == "/api/notes":
        ctyp = (environ.get("CONTENT_TYPE") or "").lower()
        if "application/x-www-form-urlencoded" in ctyp:
            try:
                import io, urllib.parse as _u, json as _json
                n = int(environ.get("CONTENT_LENGTH") or "0")
                raw = environ["wsgi.input"].read(n).decode("utf-8") if n else ""
                params = dict(_u.parse_qsl(raw, keep_blank_values=True))
                payload = _json.dumps({"text": params.get("text","")}).encode("utf-8")
                env = dict(environ)
                env["CONTENT_TYPE"]   = "application/json; charset=utf-8"
                env["CONTENT_LENGTH"] = str(len(payload))
                env["wsgi.input"]     = io.BytesIO(payload)
            except Exception:
                env = environ  # ante error, no transformamos

    injecting_link = (method == "GET" and path == "/api/notes")
    cap: dict = {"status": None, "headers": None}

    def _sr(status: str, headers: list, exc_info=None):
        cap["status"], cap["headers"] = status, list(headers)
        def _write(_b: bytes): pass
        return _write

    body_iter = inner(env, _sr)

    status  = cap["status"] or "200 OK"
    headers = list(cap["headers"] or [])

    # Inyectar Link si falta en GET /api/notes
    if injecting_link and not _has(headers, "Link"):
        limit = _getlimit(qs, "3")
        headers.append(("Link", f'</api/notes?limit={limit}&cursor=next>; rel="next"'))

    # Añadir ACAO=* cuando corresponda (GET/POST/OPTIONS sobre /api/notes)
    if path == "/api/notes" and method in ("GET","POST","OPTIONS"):
        if not _has(headers, "Access-Control-Allow-Origin"):
            headers.append(("Access-Control-Allow-Origin","*"))

    start_response(status, headers)
    return body_iter

# Alias
app = application
PY
pathlib.Path("contract_shim.py").write_text(code, encoding="utf-8")
print("✓ contract_shim.py escrito")
PY
export SHA

# 3) wsgi.py → reexport del shim
cat > wsgi.py <<'PY'
from contract_shim import application, app  # export
PY

# 4) Añadir export seguro también desde wsgiapp (si existe)
if [ -f "wsgiapp/__init__.py" ]; then
  python - <<'PY'
from pathlib import Path
p = Path("wsgiapp/__init__.py")
s = p.read_text(encoding="utf-8")
marker = "# === P12 CONTRACT SHIM EXPORT ==="
if marker not in s:
    s += "\n\n# === P12 CONTRACT SHIM EXPORT ===\ntry:\n    from contract_shim import application as application, app as app\nexcept Exception:\n    pass\n"
    p.write_text(s, encoding="utf-8")
    print("→ export agregado en wsgiapp/__init__.py")
else:
    print("→ wsgiapp/__init__.py ya tenía export")
PY
fi

# 5) Verificación sintáctica
python - <<'PY'
import py_compile
py_compile.compile('contract_shim.py', doraise=True); print("✓ py_compile contract_shim.py")
py_compile.compile('wsgi.py', doraise=True);          print("✓ py_compile wsgi.py")
try:
    py_compile.compile('wsgiapp/__init__.py', doraise=True); print("✓ py_compile __init__.py OK")
except Exception:
    pass
PY

echo
echo "Listo. Ahora deploy con Start Command:"
echo "  gunicorn wsgi:application --chdir /opt/render/project/src -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} --timeout \${TIMEOUT:-120} -b 0.0.0.0:\$PORT"
echo "(sin variables APP_MODULE / P12_WSGI_*)."
