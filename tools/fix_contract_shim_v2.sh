#!/usr/bin/env bash
set -euo pipefail

SHA="$(git rev-parse HEAD)"

# --- A) contract_shim.py ---
cat > contract_shim.py <<'PY'
import json, re, io
from urllib.parse import unquote_plus

# Embed de HEAD para /api/deploy-stamp (lo reemplazamos más abajo)
HEAD_SHA = "REPLACED_AT_BUILD"

def _b(s: str):
    return [s.encode("utf-8")]

def _has(headers, key: str) -> bool:
    k = key.lower()
    return any(h[0].lower() == k for h in headers or [])

def _build_inner():
    # 1) backend.create_app()
    try:
        from backend import create_app as _factory  # type: ignore
        return _factory()
    except Exception:
        pass
    # 2) wsgiapp._resolve_app()
    try:
        from wsgiapp import _resolve_app  # type: ignore
        return _resolve_app()
    except Exception:
        return None

def application(environ, start_response):
    path   = environ.get("PATH_INFO") or ""
    method = (environ.get("REQUEST_METHOD") or "GET").upper()
    q      = environ.get("QUERY_STRING") or ""
    accept = (environ.get("HTTP_ACCEPT") or "")

    # /api/health (dual: JSON si lo piden explícito)
    if path == "/api/health":
        if "application/json" in accept:
            start_response("200 OK", [("Content-Type","application/json; charset=utf-8")])
            return _b('{"ok": true}')
        else:
            start_response("200 OK", [("Content-Type","text/plain; charset=utf-8")])
            return _b("health ok")

    # /api/deploy-stamp (.txt o .json)
    if path == "/api/deploy-stamp" or path == "/api/deploy-stamp.json":
        if path.endswith(".json"):
            start_response("200 OK", [("Content-Type","application/json; charset=utf-8")])
            return _b(json.dumps({"rev": HEAD_SHA}))
        else:
            start_response("200 OK", [("Content-Type","text/plain; charset=utf-8")])
            return _b(HEAD_SHA)

    # CORS preflight
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

    inner = _build_inner()
    if inner is None:
        start_response("500 Internal Server Error", [("Content-Type","text/plain; charset=utf-8")])
        return _b("wsgi: sin app interna")

    # Helper para invocar y capturar status/headers/body
    def _invoke(env):
        cap = {"status": None, "headers": None, "body": b""}
        def _sr(status, headers, exc_info=None):
            cap["status"], cap["headers"] = status, list(headers or [])
            def _write(b):
                if b: cap["body"] += b
            return _write
        chunks = list(inner(env, _sr))
        if chunks:
            cap["body"] += b"".join(chunks)
        return cap

    injecting_link = (method == "GET" and path == "/api/notes")

    # --- Camino normal / posible reintento FORM→JSON ---
    if method == "POST" and path == "/api/notes":
        ctyp = (environ.get("CONTENT_TYPE") or "").lower()
        if "application/x-www-form-urlencoded" in ctyp:
            # Bufferizamos el body para poder reintentar
            try:
                n = int(environ.get("CONTENT_LENGTH") or "0")
            except Exception:
                n = 0
            raw = b""
            wsgi_input = environ.get("wsgi.input")
            if n and hasattr(wsgi_input, "read"):
                raw = wsgi_input.read(n)
            # 1ª pasada (FORM original)
            env1 = dict(environ)
            env1["CONTENT_LENGTH"] = str(len(raw))
            env1["wsgi.input"] = io.BytesIO(raw)
            r1 = _invoke(env1)
            status = r1["status"] or "200 OK"
            # Si no es 400, devolvemos tal cual
            if not status.startswith("400"):
                start_response(status, r1["headers"] or [])
                return [r1["body"]] if r1["body"] else []
            # Si fue 400, intentamos extraer text=... y reintentar como JSON
            try:
                form = raw.decode("utf-8")
            except Exception:
                form = ""
            m = re.search(r'(?:^|&)text=([^&]+)', form)
            if not m:
                start_response(status, r1["headers"] or [])
                return [r1["body"]] if r1["body"] else []
            text = unquote_plus(m.group(1))
            payload = json.dumps({"text": text}).encode("utf-8")
            env2 = dict(environ)
            env2["CONTENT_TYPE"]   = "application/json; charset=utf-8"
            env2["CONTENT_LENGTH"] = str(len(payload))
            env2["wsgi.input"]     = io.BytesIO(payload)
            r2 = _invoke(env2)
            start_response(r2["status"] or "200 OK", r2["headers"] or [])
            return [r2["body"]] if r2["body"] else []
        # Si no era form-urlencoded → camino normal
        r = _invoke(environ)
        start_response(r["status"] or "200 OK", r["headers"] or [])
        return [r["body"]] if r["body"] else []

    # GET /api/notes (inyectar Link si falta)
    cap = {"status": None, "headers": None}
    def _sr(status, headers, exc_info=None):
        cap["status"], cap["headers"] = status, list(headers or [])
        def _write(_): pass
        return _write
    out_iter = list(inner(environ, _sr))
    status = cap["status"] or "200 OK"
    headers = list(cap["headers"] or [])
    if injecting_link and not _has(headers, "Link"):
        m = re.search(r'(?:^|&)limit=([^&]+)', q or "")
        limit = m.group(1) if m else "3"
        headers.append(("Link", f'</api/notes?limit={limit}&cursor=next>; rel="next"'))
    start_response(status, headers)
    return out_iter

# Alias estándar
app = application
PY

# Incrusta el SHA actual en el shim
python - <<'PY' "${SHA}"
from pathlib import Path
import sys
sha = sys.argv[1]
p = Path("contract_shim.py")
s = p.read_text(encoding="utf-8")
p.write_text(s.replace('HEAD_SHA = "REPLACED_AT_BUILD"', f'HEAD_SHA = "{sha}"'), encoding="utf-8")
print("✓ contract_shim.py incrustó", sha)
PY

# --- B) wsgi.py que reexporta el shim ---
cat > wsgi.py <<'PY'
from contract_shim import application, app  # export directo
PY

# --- C) Hook en wsgiapp/__init__.py para reexportar el mismo shim (sin tocar helpers) ---
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
git commit -m "ops: ContractShim v2 (FORM→JSON con buffering, health dual, Link en GET) + export desde wsgi y wsgiapp"
git push origin main

echo
echo "➡️  En Render:"
echo "   • Start Command = gunicorn wsgi:application --chdir /opt/render/project/src -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} --timeout \${TIMEOUT:-120} -b 0.0.0.0:\$PORT"
echo "   • SIN variables APP_MODULE ni P12_WSGI_* en Environment."
echo "   • Clear build cache → Deploy."
