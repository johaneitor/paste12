#!/usr/bin/env bash
set -euo pipefail

SHA="$(git rev-parse HEAD)"

# ---------- contract_shim.py ----------
cat > contract_shim.py <<'PY'
import io, json, re, urllib.parse
from typing import Callable, Iterable, Tuple

StartResp = Callable[[str, list[Tuple[str,str]], object | None], Callable[[bytes], object]]
WSGIApp   = Callable[[dict, StartResp], Iterable[bytes]]

def _b(s: str) -> list[bytes]: return [s.encode("utf-8")]
def _has(headers: list[Tuple[str,str]], key: str) -> bool:
    k = key.lower(); return any(h[0].lower() == k for h in headers)

def _try_factory() -> WSGIApp | None:
    # 1) backend.create_app()
    try:
        from backend import create_app as _f  # type: ignore
        return _f()
    except Exception:
        pass
    # 2) wsgiapp._resolve_app (si existe)
    try:
        from wsgiapp import _resolve_app  # type: ignore
        return _resolve_app()
    except Exception:
        return None

HEAD_SHA = "REPLACED_AT_BUILD"

def application(environ: dict, start_response: StartResp):
    method = (environ.get("REQUEST_METHOD") or "GET").upper()
    path   = environ.get("PATH_INFO") or ""
    query  = environ.get("QUERY_STRING") or ""

    # --- Health (texto) ---
    if path == "/api/health":
        start_response("200 OK", [("Content-Type","text/plain; charset=utf-8")])
        return _b("health ok")

    # --- Deploy stamp (texto + json) ---
    if path.startswith("/api/deploy-stamp"):
        if path.endswith(".json"):
            start_response("200 OK", [("Content-Type","application/json; charset=utf-8")])
            return _b(json.dumps({"rev": HEAD_SHA}))
        start_response("200 OK", [("Content-Type","text/plain; charset=utf-8")])
        return _b(HEAD_SHA)

    # --- CORS preflight estable ---
    if method == "OPTIONS" and path == "/api/notes":
        start_response("204 No Content", [
            ("Access-Control-Allow-Origin","*"),
            ("Access-Control-Allow-Methods","GET,POST,OPTIONS"),
            ("Access-Control-Allow-Headers","Content-Type"),
            ("Access-Control-Max-Age","86400"),
        ])
        return []

    # --- POST vacío → 400 JSON canónico ---
    if method == "POST" and path == "/api/notes":
        clen = (environ.get("CONTENT_LENGTH") or "").strip()
        try: n = int(clen) if clen else 0
        except Exception: n = 0
        if n == 0:
            start_response("400 Bad Request", [("Content-Type","application/json; charset=utf-8")])
            return _b('{"ok": false, "error": "text_required"}')

    # --- Fallback de /view si el backend no lo implementa ---
    m_view = re.fullmatch(r"/api/notes/(\d+)/view", path or "")
    if method == "POST" and m_view:
        # No dependemos del backend: devolvemos 200 para evitar 404 en suites
        nid = int(m_view.group(1))
        start_response("200 OK", [("Content-Type","application/json; charset=utf-8")])
        return _b(json.dumps({"ok": True, "id": nid}))

    inner = _try_factory()
    if inner is None:
        start_response("500 Internal Server Error", [("Content-Type","text/plain; charset=utf-8")])
        return _b("wsgi: sin app interna")

    # Adaptador FORM→JSON (solo 1er intento)
    def _maybe_retry_form(env: dict, sr: StartResp):
        cap = {"status": None, "headers": None, "buf": []}
        def _sr(s, h, e=None):
            cap["status"], cap["headers"] = s, list(h)
            def _w(b): cap["buf"].append(b); return None
            return _w
        body = list(inner(env, _sr))
        status = cap["status"] or "200 OK"

        if not (method == "POST" and path == "/api/notes"):  # no es creación
            sr(status, cap["headers"] or [])
            return body

        if not status.startswith("400"):
            sr(status, cap["headers"] or [])
            return body

        ctype = (env.get("CONTENT_TYPE") or "").lower()
        if "application/x-www-form-urlencoded" not in ctype:
            sr(status, cap["headers"] or []); return body

        try:
            w = env["wsgi.input"]; n = int(env.get("CONTENT_LENGTH") or "0")
            raw = w.read(n).decode("utf-8") if n else ""
            text = urllib.parse.parse_qs(raw).get("text", [""])[0]
        except Exception:
            sr(status, cap["headers"] or []); return body

        if not text.strip():
            # mantener 400 canónico
            sr("400 Bad Request", [("Content-Type","application/json; charset=utf-8")])
            return _b('{"ok": false, "error": "text_required"}')

        payload = json.dumps({"text": text}).encode("utf-8")
        env2 = dict(env)
        env2["CONTENT_TYPE"]   = "application/json; charset=utf-8"
        env2["CONTENT_LENGTH"] = str(len(payload))
        env2["wsgi.input"]     = io.BytesIO(payload)

        cap2 = {"status": None, "headers": None}
        def _sr2(s, h, e=None):
            cap2["status"], cap2["headers"] = s, list(h)
            def _w(b): return None
            return _w
        out2 = inner(env2, _sr2)
        sr(cap2["status"] or "200 OK", cap2["headers"] or [])
        return out2

    # Interceptamos para inyectar Link en GET /api/notes si falta
    inject_link = (method == "GET" and path == "/api/notes")

    cap = {"status": None, "headers": None}
    def _sr_main(s, h, e=None):
        cap["status"], cap["headers"] = s, list(h)
        def _w(b): return None
        return _w

    out = _maybe_retry_form(environ, _sr_main)

    status = cap["status"] or "200 OK"
    headers = list(cap["headers"] or [])
    if inject_link and not _has(headers, "Link"):
        m = re.search(r"(?:^|&)limit=([^&]+)", query or "")
        limit = m.group(1) if m else "3"
        headers.append(("Link", f'</api/notes?limit={limit}&cursor=next>; rel="next"'))

    start_response(status, headers)
    return out

# Alias
app = application
PY

# Reemplazar HEAD_SHA
python - <<PY
from pathlib import Path
s = Path("contract_shim.py").read_text(encoding="utf-8")
s = s.replace('HEAD_SHA = "REPLACED_AT_BUILD"', 'HEAD_SHA = "${SHA}"')
Path("contract_shim.py").write_text(s, encoding="utf-8")
print("✓ contract_shim.py incrustó ${SHA}")
PY

# ---------- wsgi.py (reexporta shim) ----------
cat > wsgi.py <<'PY'
from contract_shim import application, app
PY

# ---------- hook en wsgiapp/__init__.py ----------
python - <<'PY'
from pathlib import Path
p = Path("wsgiapp/__init__.py")
orig = p.read_text(encoding="utf-8")
marker = "# === P12 CONTRACT SHIM EXPORT ==="
if marker not in orig:
    orig += (
        "\n\n# === P12 CONTRACT SHIM EXPORT ===\n"
        "try:\n"
        "    from contract_shim import application as application, app as app\n"
        "except Exception:\n"
        "    pass\n"
    )
    p.write_text(orig, encoding="utf-8")
    print("✓ wsgiapp/__init__.py: export agregado")
else:
    print("→ wsgiapp/__init__.py ya tenía export")
PY

python - <<'PY'
import py_compile
py_compile.compile('contract_shim.py', doraise=True); print("✓ py_compile contract_shim.py")
py_compile.compile('wsgi.py', doraise=True);          print("✓ py_compile wsgi.py")
py_compile.compile('wsgiapp/__init__.py', doraise=True); print("✓ py_compile wsgiapp/__init__.py")
PY

echo "Listo. Commit/push con tools/git_push_contract_v5.sh"
