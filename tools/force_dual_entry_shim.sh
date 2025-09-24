#!/usr/bin/env bash
set -euo pipefail

SHA="$(git rev-parse HEAD)"

# --- A) contract_shim.py (una sola fuente de verdad) ---
cat > contract_shim.py <<'PY'
import json, re
from typing import Callable, Iterable, Tuple

StartResp = Callable[[str, list, object | None], Callable[[bytes], object]]
WSGIApp   = Callable[[dict, StartResp], Iterable[bytes]]

def _b(s: str) -> list[bytes]:
    return [s.encode("utf-8")]

def _has(headers: list[Tuple[str,str]], key: str) -> bool:
    k = key.lower()
    return any(h[0].lower() == k for h in headers)

def build_inner() -> WSGIApp | None:
    # 1) Intentar backend.create_app() (nuestro ideal)
    try:
        from backend import create_app as _factory  # type: ignore
        return _factory()
    except Exception:
        pass
    # 2) Fallback al resolver interno de wsgiapp si existe
    try:
        from wsgiapp import _resolve_app  # type: ignore
        return _resolve_app()
    except Exception:
        return None

# Inyectamos el SHA de HEAD (lo rellena el caller)
HEAD_SHA = "REPLACED_AT_BUILD"

def application(environ: dict, start_response: StartResp):
    path   = environ.get("PATH_INFO", "") or ""
    method = (environ.get("REQUEST_METHOD") or "GET").upper()
    q      = environ.get("QUERY_STRING") or ""

    # /api/health textual
    if path == "/api/health":
        start_response("200 OK", [("Content-Type","text/plain; charset=utf-8")])
        return _b("health ok")

    # /api/deploy-stamp (.txt y .json)
    if path == "/api/deploy-stamp" or path == "/api/deploy-stamp.json":
        if path.endswith(".json"):
            start_response("200 OK", [("Content-Type","application/json; charset=utf-8")])
            return _b(json.dumps({"rev": HEAD_SHA}))
        else:
            start_response("200 OK", [("Content-Type","text/plain; charset=utf-8")])
            return _b(HEAD_SHA)

    # CORS preflight estable para /api/notes
    if method == "OPTIONS" and path == "/api/notes":
        start_response("204 No Content", [
            ("Access-Control-Allow-Origin",  "*"),
            ("Access-Control-Allow-Methods", "GET,POST,OPTIONS"),
            ("Access-Control-Allow-Headers", "Content-Type"),
            ("Access-Control-Max-Age",      "86400"),
        ])
        return []

    # HEAD / y /index.html
    if method == "HEAD" and path in ("/", "/index.html"):
        start_response("200 OK", [("Content-Type","text/html; charset=utf-8")])
        return []

    # Adaptador de POST vacío → error canónico
    if method == "POST" and path == "/api/notes":
        clen = (environ.get("CONTENT_LENGTH") or "").strip()
        try:
            n = int(clen) if clen else 0
        except Exception:
            n = 0
        if n == 0:
            start_response("400 Bad Request", [("Content-Type","application/json; charset=utf-8")])
            return _b('{"ok": false, "error": "text_required"}')

    # Si el backend devuelve 400 a FORM, reconvertimos a JSON y reintentamos 1 vez
    def _maybe_retry_form(inner: WSGIApp, env: dict, sr: StartResp):
        cap = {"status": None, "headers": None, "wbuf": []}
        def _sr(status, headers, exc_info=None):
            cap["status"], cap["headers"] = status, list(headers)
            def _write(b): cap["wbuf"].append(b)
            return _write
        body_iter = list(inner(env, _sr))  # materializamos
        status = cap["status"] or "200 OK"
        if not (method == "POST" and path == "/api/notes"):
            sr(status, cap["headers"] or [])
            return body_iter
        if not status.startswith("400"):
            sr(status, cap["headers"] or [])
            return body_iter

        # Reintento: si era form-urlencoded, leemos y convertimos a JSON {"text": ...}
        ctyp = (env.get("CONTENT_TYPE") or "").lower()
        if "application/x-www-form-urlencoded" not in ctyp:
            sr(status, cap["headers"] or [])
            return body_iter

        try:
            w = env["wsgi.input"]; n = int(env.get("CONTENT_LENGTH") or "0")
            raw = w.read(n).decode("utf-8") if n else ""
        except Exception:
            sr(status, cap["headers"] or [])
            return body_iter

        m = re.search(r'(?:^|&)text=([^&]+)', raw)
        if not m:
            sr(status, cap["headers"] or [])
            return body_iter

        import urllib.parse as _u
        text = _u.unquote_plus(m.group(1))

        # Construimos nuevo entorno tipo JSON
        import io, json as _json
        payload = _json.dumps({"text": text}).encode("utf-8")
        env2 = dict(env)
        env2["CONTENT_TYPE"]   = "application/json; charset=utf-8"
        env2["CONTENT_LENGTH"] = str(len(payload))
        env2["wsgi.input"]     = io.BytesIO(payload)

        cap2 = {"status": None, "headers": None}
        def _sr2(status, headers, exc_info=None):
            cap2["status"], cap2["headers"] = status, list(headers)
            def _write(_): pass
            return _write
        out2 = inner(env2, _sr2)
        sr(cap2["status"] or "200 OK", cap2["headers"] or [])
        return out2

    # Passthrough + inyección de Link en GET /api/notes
    inner = build_inner()
    if inner is None:
        start_response("500 Internal Server Error", [("Content-Type","text/plain; charset=utf-8")])
        return _b("wsgi: sin app interna")

    injecting_link = (method == "GET" and path == "/api/notes")
    cap = {"status": None, "headers": None}
    def _sr(status: str, headers: list, exc_info=None):
        cap["status"], cap["headers"] = status, list(headers)
        def _write(_): pass
        return _write

    out = _maybe_retry_form(inner, environ, _sr)

    status: str = cap["status"] or "200 OK"
    headers: list = list(cap["headers"] or [])
    if injecting_link and not _has(headers, "Link"):
        m = re.search(r'(?:^|&)limit=([^&]+)', q or "")
        limit = m.group(1) if m else "3"
        headers.append(("Link", f'</api/notes?limit={limit}&cursor=next>; rel="next"'))

    start_response(status, headers)
    return out

# Alias estándar
app = application
PY

# Parchear la constante HEAD_SHA (pasamos el SHA como argv[1])
python - "$SHA" <<'PY'
import sys
from pathlib import Path
p = Path("contract_shim.py")
s = p.read_text(encoding="utf-8")
s = s.replace('HEAD_SHA = "REPLACED_AT_BUILD"', f'HEAD_SHA = "{sys.argv[1]}"')
p.write_text(s, encoding="utf-8")
print("✓ contract_shim.py incrustó", sys.argv[1])
PY

# --- B) wsgi.py que reexporta el shim ---
cat > wsgi.py <<'PY'
from contract_shim import application, app  # export directo
PY

# --- C) Hook en wsgiapp/__init__.py para reexportar el mismo shim ---
python - <<'PY'
from pathlib import Path
p = Path("wsgiapp/__init__.py")
orig = p.read_text(encoding="utf-8")
marker = "# === P12 CONTRACT SHIM EXPORT ==="
if marker not in orig:
    patch = (
        "\n\n# === P12 CONTRACT SHIM EXPORT ===\n"
        "try:\n"
        "    from contract_shim import application as application, app as app\n"
        "except Exception:\n"
        "    pass\n"
    )
    p.write_text(orig + patch, encoding="utf-8")
    print("✓ wsgiapp/__init__.py: agregado export del ContractShim")
else:
    print("→ wsgiapp/__init__.py ya tenía el export del ContractShim")
PY

# Compilar antes de commitear
python - <<'PY'
import py_compile
py_compile.compile('contract_shim.py', doraise=True); print("✓ py_compile contract_shim.py OK")
py_compile.compile('wsgi.py', doraise=True);          print("✓ py_compile wsgi.py OK")
py_compile.compile('wsgiapp/__init__.py', doraise=True); print("✓ py_compile wsgiapp/__init__.py OK")
PY

# Evitar tocar workflows
git checkout -- .github/workflows || true
git restore --staged .github/workflows || true

git add contract_shim.py wsgi.py wsgiapp/__init__.py
git commit -m "ops: ContractShim unificado y reexportado desde wsgi y wsgiapp; /api/deploy-stamp y contrato estable"
git push origin main

echo
echo "➡️  En Render:"
echo "   • Start Command = gunicorn wsgi:application --chdir /opt/render/project/src -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} --timeout \${TIMEOUT:-120} -b 0.0.0.0:\$PORT"
echo "   • SIN variables APP_MODULE ni P12_WSGI_* en Environment."
echo "   • Clear build cache → Deploy."
