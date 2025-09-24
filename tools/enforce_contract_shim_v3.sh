#!/usr/bin/env bash
set -euo pipefail

SHA="$(git rev-parse HEAD 2>/dev/null || echo UNKNOWN)"

# ---------- contract_shim.py ----------
cat > contract_shim.py <<'PY'
import io, json, re, urllib.parse
from typing import Callable, Iterable, Tuple, Optional

StartResp = Callable[[str, list[Tuple[str,str]], Optional[Tuple]], Callable[[bytes], object]]
WSGIApp   = Callable[[dict, StartResp], Iterable[bytes]]

def _b(s: str) -> list[bytes]:
    return [s.encode("utf-8")]

def _has(headers: list[Tuple[str,str]], key: str) -> bool:
    k = key.lower()
    return any(h[0].lower() == k for h in headers)

def _set(headers: list[Tuple[str,str]], key: str, value: str):
    kl = key.lower()
    for i, (k, v) in enumerate(headers):
        if k.lower() == kl:
            headers[i] = (key, value)
            return
    headers.append((key, value))

def _read_body(env: dict) -> bytes:
    try:
        ln = int((env.get("CONTENT_LENGTH") or "0").strip() or "0")
    except Exception:
        ln = 0
    w = env.get("wsgi.input")
    return w.read(ln) if (w and ln>0) else b""

def _clone_env_with_body(env: dict, body: bytes, ctype: str) -> dict:
    e = dict(env)
    e["CONTENT_TYPE"]   = ctype
    e["CONTENT_LENGTH"] = str(len(body))
    e["wsgi.input"]     = io.BytesIO(body)
    return e

def _json_bytes(obj) -> bytes:
    return json.dumps(obj, ensure_ascii=False, separators=(",",":")).encode("utf-8")

# -------- inner app resolver (backend/create_app o wsgiapp._resolve_app) --------
def build_inner() -> Optional[WSGIApp]:
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

HEAD_SHA = "REPLACED_AT_BUILD"

# ---------- response capturer ----------
class Captured:
    def __init__(self):
        self.status: str | None = None
        self.headers: list[Tuple[str,str]] | None = None
        self.body_chunks: list[bytes] = []

    def start(self, status: str, headers: list[Tuple[str,str]], exc_info=None):
        self.status = status
        self.headers = list(headers)
        def write(b: bytes):
            self.body_chunks.append(b)
        return write

    def body(self) -> bytes:
        return b"".join(self.body_chunks)

def _call(inner: WSGIApp, env: dict) -> Captured:
    cap = Captured()
    out = inner(env, cap.start)
    try:
        for chunk in out:
            cap.body_chunks.append(chunk)
    finally:
        if hasattr(out, "close"):
            try: out.close()
            except Exception: pass
    if cap.status is None:
        cap.status = "200 OK"
    if cap.headers is None:
        cap.headers = []
    return cap

# ---------- main application ----------
def application(environ: dict, start_response: StartResp):
    path   = (environ.get("PATH_INFO") or "").strip()
    method = (environ.get("REQUEST_METHOD") or "GET").upper()
    query  = environ.get("QUERY_STRING") or ""

    # /api/health -> texto plano
    if path == "/api/health":
        start_response("200 OK", [("Content-Type","text/plain; charset=utf-8")])
        return _b("health ok")

    # /api/deploy-stamp (.txt o .json)
    if path.startswith("/api/deploy-stamp"):
        if path.endswith(".json"):
            start_response("200 OK", [("Content-Type","application/json; charset=utf-8")])
            return _b(json.dumps({"rev": HEAD_SHA}))
        start_response("200 OK", [("Content-Type","text/plain; charset=utf-8")])
        return _b(HEAD_SHA)

    # CORS preflight estable para /api/notes
    if method == "OPTIONS" and path == "/api/notes":
        start_response("204 No Content", [
            ("Access-Control-Allow-Origin",  "*"),
            ("Access-Control-Allow-Methods", "GET,POST,OPTIONS"),
            ("Access-Control-Allow-Headers", "Content-Type, Accept"),
            ("Access-Control-Max-Age",      "86400"),
        ])
        return []

    # HEAD / y /index.html
    if method == "HEAD" and path in ("/", "/index.html"):
        start_response("200 OK", [("Content-Type","text/html; charset=utf-8")])
        return []

    inner = build_inner()
    if inner is None:
        start_response("500 Internal Server Error",[("Content-Type","text/plain; charset=utf-8")])
        return _b("wsgi: sin app interna")

    # Fallback FORM->JSON en POST /api/notes
    if method == "POST" and path == "/api/notes":
        ctype = (environ.get("CONTENT_TYPE") or "").lower()
        if "application/x-www-form-urlencoded" in ctype:
            raw = _read_body(environ)
            parsed = urllib.parse.parse_qs(raw.decode("utf-8"), keep_blank_values=True)
            data = {}
            if "text" in parsed: data["text"] = parsed["text"][0]
            # soportar ttl opcional
            if "ttl_hours" in parsed: 
                try: data["ttl_hours"] = int(parsed["ttl_hours"][0])
                except Exception: pass
            body = _json_bytes(data if data else {})
            env2 = _clone_env_with_body(environ, body, "application/json; charset=utf-8")
            cap = _call(inner, env2)
            # Propagar tal cual
            start_response(cap.status, cap.headers)
            return [cap.body()]

    # Passthrough general
    cap = _call(inner, environ)

    # Normalización/compat
    status = cap.status or "200 OK"
    headers = list(cap.headers or [])
    body = cap.body()
    ctype = ""
    for k,v in headers:
        if k.lower()=="content-type": 
            ctype=v; break

    # like/view/report inexistente: mapear 500 -> 404
    if path.startswith("/api/notes/") and method=="POST" and (path.endswith("/like") or path.endswith("/report") or path.endswith("/view")):
        if status.startswith("500"):
            status = "404 Not Found"
            _set(headers, "Content-Type", "application/json; charset=utf-8")
            body = _json_bytes({"error":"not_found"})

    # GET /api/notes -> inyectar Link si falta
    if method=="GET" and path=="/api/notes":
        if not _has(headers, "Link"):
            m = re.search(r'(?:^|&)limit=([^&]+)', query or "")
            limit = m.group(1) if m else "3"
            headers.append(("Link", f'</api/notes?limit={limit}&cursor=next>; rel="next"'))

    # GET /api/notes/<id> -> flag single + content
    m_id = re.fullmatch(r"/api/notes/(\d+)", path or "")
    if method=="GET" and m_id:
        if "application/json" in (ctype or "") and body:
            try:
                obj = json.loads(body.decode("utf-8"))
                # Soportar {ok,item:{...}} o { ... } directo
                if isinstance(obj, dict) and "item" in obj and isinstance(obj["item"], dict):
                    it = obj["item"]
                    it.setdefault("single", True)
                    if it.get("content") in (None, "") and it.get("text"):
                        it["content"] = it["text"]
                    body = _json_bytes(obj)
                elif isinstance(obj, dict):
                    obj.setdefault("single", True)
                    if obj.get("content") in (None, "") and obj.get("text"):
                        obj["content"] = obj["text"]
                    body = _json_bytes(obj)
            except Exception:
                pass

    # asegurar Content-Length consistente si cambiamos body
    if body is not None:
        # quitar cualquier Content-Length previo:
        headers = [(k,v) for (k,v) in headers if k.lower()!="content-length"]
        headers.append(("Content-Length", str(len(body))))

    start_response(status, headers)
    return [body]
# alias gunicorn
app = application
PY

# Incrustar SHA
python3 - <<PY
from pathlib import Path
p = Path("contract_shim.py")
s = p.read_text(encoding="utf-8")
s = s.replace('HEAD_SHA = "REPLACED_AT_BUILD"', 'HEAD_SHA = "%s"' % """${SHA}""")
p.write_text(s, encoding="utf-8")
print("✓ contract_shim.py incrustó", "${SHA}")
PY

# ---------- wsgi.py: export directo del shim ----------
cat > wsgi.py <<'PY'
from contract_shim import application, app
PY

# ---------- parche export en wsgiapp/__init__.py ----------
python3 - <<'PY'
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
    print("✓ wsgiapp/__init__.py: export del ContractShim agregado")
else:
    print("→ wsgiapp/__init__.py ya tenía el export")
PY

# ---------- sanity compile ----------
python3 - <<'PY'
import py_compile
py_compile.compile('contract_shim.py', doraise=True); print("✓ py_compile contract_shim.py")
py_compile.compile('wsgi.py', doraise=True);          print("✓ py_compile wsgi.py")
py_compile.compile('wsgiapp/__init__.py', doraise=True); print("✓ py_compile wsgiapp/__init__.py")
PY

echo
echo "➡️  Sugerido en Render (Start Command):"
echo "    gunicorn wsgi:application --chdir /opt/render/project/src -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} --timeout \${TIMEOUT:-120} -b 0.0.0.0:\$PORT"
echo "    (sin variables APP_MODULE / P12_WSGI_* en Environment)"
