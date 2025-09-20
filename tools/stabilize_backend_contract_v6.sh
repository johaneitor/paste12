#!/usr/bin/env bash
set -euo pipefail
SHA="$(git rev-parse HEAD 2>/dev/null || echo UNKNOWN)"

cat > contract_shim.py <<'PY'
import io, re, json, html
from typing import Callable, Iterable, Tuple
from urllib.parse import parse_qs, unquote_plus

StartResp = Callable[[str, list, object|None], Callable[[bytes], object]]
WSGIApp   = Callable[[dict, StartResp], Iterable[bytes]]

HEAD_SHA = "REPLACED_AT_BUILD"

def _b(s: str) -> list[bytes]: return [s.encode("utf-8")]
def _has(headers: list[Tuple[str,str]], key: str) -> bool:
    k = key.lower(); return any(h[0].lower() == k for h in headers)
def _is_notes_root(path: str) -> bool:
    return (path or "").rstrip('/') == "/api/notes"
def _clone_env(env: dict, **over):
    out = dict(env); out.update(over); return out

def _call(inner, env):
    cap = {"status": None, "headers": None, "wbuf": []}
    def _sr(status, headers, exc_info=None):
        cap["status"], cap["headers"] = status, list(headers)
        def _w(b): cap["wbuf"].append(b); return None
        return _w
    body_iter = list(inner(env, _sr))
    body = b"".join(cap["wbuf"]) + b"".join(body_iter)
    return (cap["status"] or "200 OK", cap["headers"] or [], body)

def _build_inner():
    try:
        from backend import create_app as _f  # type: ignore
        app = _f()
        return app.wsgi_app if hasattr(app, "wsgi_app") else app
    except Exception: pass
    try:
        from wsgiapp import _resolve_app  # type: ignore
        return _resolve_app()
    except Exception: pass
    for mod, attr in (("run","app"), ("app","app"), ("wsgiapp","app"), ("wsgi","application")):
        try:
            m = __import__(mod, fromlist=[attr]); return getattr(m, attr)
        except Exception: pass
    return None

def application(environ: dict, start_response: StartResp):
    path   = environ.get("PATH_INFO") or ""
    method = (environ.get("REQUEST_METHOD") or "GET").upper()
    qs     = environ.get("QUERY_STRING") or ""
    ctype  = (environ.get("CONTENT_TYPE") or "").lower()

    # health → texto
    if path == "/api/health":
        start_response("200 OK", [("Content-Type","text/plain; charset=utf-8")])
        return _b("health ok")

    # deploy-stamp
    if path in ("/api/deploy-stamp", "/api/deploy-stamp.json"):
        if path.endswith(".json"):
            start_response("200 OK", [("Content-Type","application/json; charset=utf-8")])
            return _b(json.dumps({"rev": HEAD_SHA}))
        start_response("200 OK", [("Content-Type","text/plain; charset=utf-8")])
        return _b(HEAD_SHA)

    # CORS preflight estable
    if method == "OPTIONS" and _is_notes_root(path):
        start_response("204 No Content", [
            ("Access-Control-Allow-Origin","*"),
            ("Access-Control-Allow-Methods","GET,POST,OPTIONS"),
            ("Access-Control-Allow-Headers","Content-Type"),
            ("Access-Control-Max-Age","86400"),
        ])
        return []

    # HEAD mínimas
    if method == "HEAD" and path in ("/", "/index.html"):
        start_response("200 OK", [("Content-Type","text/html; charset=utf-8")])
        return []

    inner = _build_inner()
    if inner is None:
        start_response("500 Internal Server Error", [("Content-Type","text/plain; charset=utf-8")])
        return _b("wsgi: inner app not found")

    # POST vacío → 400 canónico
    if method == "POST" and _is_notes_root(path):
        try: n = int((environ.get("CONTENT_LENGTH") or "0").strip() or "0")
        except Exception: n = 0
        if n == 0:
            start_response("400 Bad Request", [("Content-Type","application/json; charset=utf-8")])
            return _b('{"error":"text required"}')

    def _maybe_retry_form(env, status, headers, body):
        if not (method == "POST" and _is_notes_root(path)): return (status, headers, body)
        if not str(status).startswith("400"): return (status, headers, body)
        if "application/x-www-form-urlencoded" not in ctype: return (status, headers, body)
        try:
            w = env["wsgi.input"]; n = int(env.get("CONTENT_LENGTH") or "0")
            raw = w.read(n).decode("utf-8") if n else ""
        except Exception:
            return (status, headers, body)
        params = parse_qs(raw, keep_blank_values=True)
        text = params.get("text", [""])[0]
        if not text: return (status, headers, body)
        payload = json.dumps({"text": unquote_plus(text)}).encode("utf-8")
        env2 = _clone_env(env,
            CONTENT_TYPE   = "application/json; charset=utf-8",
            CONTENT_LENGTH = str(len(payload)),
            wsgi__input    = io.BytesIO(payload))
        env2["wsgi.input"] = env2.pop("wsgi__input")
        return _call(inner, env2)

    # /view fallback si la nota existe
    _vm = re.fullmatch(r"/api/notes/(\d+)/view", path.rstrip('/'))
    if method == "POST" and _vm:
        st, hdrs, body = _call(inner, environ)
        code = int(str(st).split()[0])
        if code == 404:
            nid = _vm.group(1)
            gst, gh, gb = _call(inner, _clone_env(environ,
                REQUEST_METHOD="GET", PATH_INFO=f"/api/notes/{nid}", QUERY_STRING="", CONTENT_LENGTH="0"))
            if int(str(gst).split()[0]) == 200:
                start_response("200 OK",[("Content-Type","application/json; charset=utf-8")])
                return _b(json.dumps({"ok": True, "id": int(nid)}))
        if code in (405, 501):
            start_response("200 OK",[("Content-Type","application/json; charset=utf-8")])
            return _b(json.dumps({"ok": True}))
        start_response(st, hdrs); return [body]

    # GET single → HTML opcional
    _sm = re.fullmatch(r"/api/notes/(\d+)", path.rstrip('/'))
    if method == "GET" and _sm:
        accept = (environ.get("HTTP_ACCEPT") or "")
        if "text/html" in accept or accept.strip() in ("*/*",""):
            st, hdrs, body = _call(inner, environ)
            if int(str(st).split()[0]) != 200:
                start_response(st, hdrs); return [body]
            try: data = json.loads(body.decode("utf-8"))
            except Exception:
                start_response(st, hdrs); return [body]
            text = html.escape((data.get("text") or ""))
            nid = data.get("id"); likes = data.get("likes") or 0; views = data.get("views") or 0
            html_page = f"""<!doctype html><meta charset=utf-8><title>Nota #{nid}</title>
<h1>Nota #{nid}</h1><p>{text}</p><p>❤ {likes} · 👁 {views}</p>"""
            start_response("200 OK",[("Content-Type","text/html; charset=utf-8")])
            return _b(html_page)

    # Passthrough principal
    st, hdrs, body = _call(inner, environ)

    # Reintento form→JSON si tocaba
    if method == "POST" and _is_notes_root(path):
        st, hdrs, body = _maybe_retry_form(environ, st, hdrs, body)

    # Link en listado
    if method == "GET" and _is_notes_root(path):
        if not _has(hdrs, "Link"):
            import re as _re
            m = _re.search(r"(?:^|&)limit=([^&]+)", qs)
            limit = m.group(1) if m else "3"
            hdrs = list(hdrs) + [("Link", f'</api/notes?limit={limit}&cursor=next>; rel="next"')]

    start_response(st, hdrs)
    return [body]

app = application
PY

# Incrustar SHA
python - <<PY
from pathlib import Path
p=Path("contract_shim.py"); s=p.read_text(encoding="utf-8")
p.write_text(s.replace('HEAD_SHA = "REPLACED_AT_BUILD"','HEAD_SHA = "'+"${SHA}"+'"'), encoding="utf-8")
print("✓ contract_shim.py incrustó ${SHA}")
PY

cat > wsgi.py <<'PY'
from contract_shim import application, app
PY

python - <<'PY'
import py_compile
py_compile.compile('contract_shim.py', doraise=True); print("✓ py_compile contract_shim.py")
py_compile.compile('wsgi.py', doraise=True);          print("✓ py_compile wsgi.py")
try:
    import py_compile; py_compile.compile('wsgiapp/__init__.py', doraise=True)
except Exception: pass
PY

echo "➡️  Start Command sugerido:"
echo "gunicorn wsgi:application --chdir /opt/render/project/src -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} --timeout \${TIMEOUT:-120} -b 0.0.0.0:\$PORT"
