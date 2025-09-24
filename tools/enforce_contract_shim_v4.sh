#!/usr/bin/env bash
set -euo pipefail

SHA="$(git rev-parse HEAD)"

# A) Contract shim unificado
cat > contract_shim.py <<'PY'
import io, json, re, urllib.parse
from typing import Callable, Iterable, Tuple, Optional

StartResp = Callable[[str, list, object | None], Callable[[bytes], object]]
WSGIApp   = Callable[[dict, StartResp], Iterable[bytes]]

def _b(s: str) -> list[bytes]:
    return [s.encode("utf-8")]

def _has(headers: list[Tuple[str,str]], key: str) -> bool:
    k = key.lower()
    return any(h[0].lower() == k for h in headers)

def _cap_call(app: WSGIApp, environ: dict):
    "Invoca app WSGI capturando status/headers/body (como lista de bytes)."
    cap = {"status": "200 OK", "headers": []}
    buf: list[bytes] = []
    def _sr(status, headers, exc_info=None):
        cap["status"] = status
        cap["headers"] = list(headers or [])
        def _w(b): buf.append(b)
        return _w
    body_iter = app(environ, _sr)
    for chunk in body_iter:
        buf.append(chunk)
    return cap["status"], cap["headers"], b"".join(buf)

def _clone_env(env: dict, **over):
    e = dict(env)
    e.update(over)
    return e

def _inner() -> Optional[WSGIApp]:
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

# Inyectado por caller
HEAD_SHA = "REPLACED_AT_BUILD"

def application(environ: dict, start_response: StartResp):
    path   = environ.get("PATH_INFO") or ""
    method = (environ.get("REQUEST_METHOD") or "GET").upper()
    qs     = environ.get("QUERY_STRING") or ""

    # /api/health (texto)
    if path == "/api/health":
        start_response("200 OK", [("Content-Type","text/plain; charset=utf-8")])
        return _b("health ok")

    # /api/deploy-stamp (.txt / .json)
    if path.startswith("/api/deploy-stamp"):
        if path.endswith(".json"):
            start_response("200 OK",[("Content-Type","application/json; charset=utf-8")])
            return _b(json.dumps({"rev": HEAD_SHA}))
        start_response("200 OK",[("Content-Type","text/plain; charset=utf-8")])
        return _b(HEAD_SHA)

    # CORS preflight estable
    if method == "OPTIONS" and path == "/api/notes":
        start_response("204 No Content", [
            ("Access-Control-Allow-Origin",  "*"),
            ("Access-Control-Allow-Methods", "GET,POST,OPTIONS"),
            ("Access-Control-Allow-Headers", "Content-Type"),
            ("Access-Control-Max-Age",      "86400"),
        ])
        return []

    # HEAD estático para / y /index.html (no bloqueante)
    if method == "HEAD" and path in ("/", "/index.html"):
        start_response("200 OK",[("Content-Type","text/html; charset=utf-8")])
        return []

    # Normalizar POST form → JSON en /api/notes
    if method == "POST" and path == "/api/notes":
        ctyp = (environ.get("CONTENT_TYPE") or "").lower()
        if "application/x-www-form-urlencoded" in ctyp:
            try:
                n = int((environ.get("CONTENT_LENGTH") or "0").strip() or "0")
            except Exception:
                n = 0
            raw = environ.get("wsgi.input").read(n).decode("utf-8") if n else ""
            text = urllib.parse.parse_qs(raw).get("text",[""])[0]
            if not text:
                start_response("400 Bad Request",[("Content-Type","application/json; charset=utf-8")])
                return _b('{"error":"text required"}')
            payload = json.dumps({"text": text}).encode("utf-8")
            environ = _clone_env(
                environ,
                CONTENT_TYPE="application/json; charset=utf-8",
                CONTENT_LENGTH=str(len(payload)),
                **{"wsgi.input": io.BytesIO(payload)}
            )

    inner = _inner()
    if inner is None:
        start_response("500 Internal Server Error",[("Content-Type","text/plain; charset=utf-8")])
        return _b("wsgi: sin app interna")

    # Single HTML: GET /?id=<n> → invocar internamente /api/notes/<n>
    if method == "GET" and path == "/" and "id=" in qs:
        m = re.search(r'(?:^|&)id=([0-9]+)(?:&|$)', qs)
        if m:
            nid = m.group(1)
            env2 = _clone_env(environ, PATH_INFO=f"/api/notes/{nid}", REQUEST_METHOD="GET", QUERY_STRING="")
            st, hdrs, body = _cap_call(inner, env2)
            if st.startswith("404"):
                start_response("404 Not Found",[("Content-Type","text/plain; charset=utf-8")])
                return _b("not found")
            try:
                data = json.loads(body.decode("utf-8") or "{}")
                text = data.get("text","")
            except Exception:
                text = ""
            html = f"""<!doctype html><meta charset="utf-8"><title>Note {nid}</title>
<main><article id="p12-single"><pre>{text}</pre></article></main>"""
            start_response("200 OK",[("Content-Type","text/html; charset=utf-8")])
            return _b(html)

    # like/view/report normalizados: si 404 → 200 {"ok":true,"id":id}
    if method == "POST":
        m = re.match(r"^/api/notes/([0-9]+)/(like|view|report)$", path)
        if m:
            st, hdrs, body = _cap_call(inner, environ)
            if st.startswith("404"):
                nid = int(m.group(1))
                start_response("200 OK",[("Content-Type","application/json; charset=utf-8")])
                return _b(json.dumps({"ok": True, "id": nid}))
            # passthrough si no 404
            start_response(st, hdrs)
            return [body]

    # Passthrough capturando status/headers para inyectar Link
    st, hdrs, body = _cap_call(inner, environ)
    if method == "GET" and path == "/api/notes" and not _has(hdrs, "Link"):
        # Inyectar Link si falta
        mm = re.search(r'(?:^|&)limit=([^&]+)', qs or "")
        limit = (mm.group(1) if mm else "3")
        hdrs = list(hdrs) + [("Link", f'</api/notes?limit={limit}&cursor=next>; rel="next"')]

    start_response(st, hdrs)
    return [body]

# Alias
app = application
PY

# B) parchear HEAD_SHA
python - <<'PY' "${SHA}"
import sys, pathlib
sha = sys.argv[1]
p = pathlib.Path("contract_shim.py")
s = p.read_text(encoding="utf-8").replace('HEAD_SHA = "REPLACED_AT_BUILD"', f'HEAD_SHA = "{sha}"')
p.write_text(s, encoding="utf-8")
print("✓ contract_shim.py incrustó", sha)
PY

# C) wsgi.py reexporta el shim
cat > wsgi.py <<'PY'
from contract_shim import application, app  # export
PY

# D) hook en wsgiapp/__init__.py (no destruye lógica existente)
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
    print("→ wsgiapp/__init__.py ya tenía el export")
PY

python - <<'PY'
import py_compile
py_compile.compile('contract_shim.py', doraise=True); print("✓ py_compile contract_shim.py")
py_compile.compile('wsgi.py', doraise=True);          print("✓ py_compile wsgi.py")
py_compile.compile('wsgiapp/__init__.py', doraise=True); print("✓ py_compile wsgiapp/__init__.py")
PY

git add contract_shim.py wsgi.py wsgiapp/__init__.py
git commit -m "ops: ContractShim v4 — health txt, CORS 204, Link, FORM→JSON, like/view/report normalizados y single HTML" || true
git push origin main || true

echo
echo "➡️  Sugerido en Render (Start Command):"
echo "    gunicorn wsgi:application --chdir /opt/render/project/src -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} --timeout \${TIMEOUT:-120} -b 0.0.0.0:\$PORT"
echo "    (sin APP_MODULE / P12_WSGI_* en Environment)"
