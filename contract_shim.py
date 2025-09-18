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
HEAD_SHA = "354f78a6d4bba30bf08ba9b50ca29527f8761e28"

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
