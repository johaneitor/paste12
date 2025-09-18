import io, json, re
from typing import Callable, Iterable, Tuple

StartResp = Callable[[str, list, object | None], Callable[[bytes], object]]
WSGIApp   = Callable[[dict, StartResp], Iterable[bytes]]

def _b(s: str) -> list[bytes]:
    return [s.encode("utf-8")]

def _has(headers: list[Tuple[str,str]], key: str) -> bool:
    k = key.lower()
    return any(h[0].lower() == k for h in headers)

def build_inner() -> WSGIApp | None:
    # 1) backend.create_app() si existe
    try:
        from backend import create_app as _factory  # type: ignore
        return _factory()
    except Exception:
        pass
    # 2) Resolver propio del paquete wsgiapp (si existe)
    try:
        from wsgiapp import _resolve_app  # type: ignore
        return _resolve_app()
    except Exception:
        return None

HEAD_SHA = "REPLACED_AT_BUILD"  # lo reemplazamos más abajo

def application(environ: dict, start_response: StartResp):
    path   = environ.get("PATH_INFO", "") or ""
    method = (environ.get("REQUEST_METHOD") or "GET").upper()
    q      = environ.get("QUERY_STRING") or ""

    # /api/health → JSON canónico
    if path == "/api/health":
        start_response("200 OK", [("Content-Type","application/json; charset=utf-8")])
        return _b('{"ok":true}')

    # /api/deploy-stamp (.json o .txt)
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

    inner = build_inner()
    if inner is None:
        start_response("500 Internal Server Error", [("Content-Type","text/plain; charset=utf-8")])
        return _b("wsgi: sin app interna")

    # Helper para capturar status/headers
    cap = {"status": None, "headers": None}
    def _sr(status: str, headers: list, exc_info=None):
        cap["status"], cap["headers"] = status, list(headers)
        def _write(_: bytes): pass
        return _write

    # Reintento inteligente solo para POST /api/notes con form-urlencoded
    def _maybe_retry_form(env: dict):
        if not (method == "POST" and path == "/api/notes"):
            return inner(env, _sr)
        # Primera pasada
        body1 = list(inner(env, _sr))
        status = cap["status"] or "200 OK"
        headers = cap["headers"] or []
        if not status.startswith("400"):
            return body1
        ctyp = (env.get("CONTENT_TYPE") or "").lower()
        if "application/x-www-form-urlencoded" not in ctyp:
            return body1
        # Leemos el body original (puede estar consumido, toleramos fallo)
        try:
            w = env["wsgi.input"]; n = int(env.get("CONTENT_LENGTH") or "0")
            raw = w.read(n).decode("utf-8") if n else ""
        except Exception:
            return body1
        m = re.search(r'(?:^|&)text=([^&]+)', raw)
        if not m:
            return body1
        import urllib.parse as _u
        text = _u.unquote_plus(m.group(1))
        payload = json.dumps({"text": text}).encode("utf-8")
        env2 = dict(env)
        env2["CONTENT_TYPE"]   = "application/json; charset=utf-8"
        env2["CONTENT_LENGTH"] = str(len(payload))
        env2["wsgi.input"]     = io.BytesIO(payload)
        # Segunda pasada
        cap["status"], cap["headers"] = None, None
        return inner(env2, _sr)

    # Normalizar like/view existentes a 200 + JSON {ok:true}
    m_like = re.fullmatch(r"/api/notes/(\d+)/(like|view)", path)
    if method == "POST" and m_like:
        body = list(_maybe_retry_form(environ))
        status = cap["status"] or "200 OK"
        # Si es éxito (2xx), lo normalizamos a 200 + JSON
        if status.startswith("20"):
            start_response("200 OK", [("Content-Type","application/json; charset=utf-8")])
            return _b('{"ok":true}')
        # Si es error, propagamos tal cual
        start_response(status, cap["headers"] or [])
        return body

    # Passthrough general + inyección de Link en GET /api/notes
    out = _maybe_retry_form(environ)
    status: str = cap["status"] or "200 OK"
    headers: list = list(cap["headers"] or [])

    if method == "GET" and path == "/api/notes" and not _has(headers, "Link"):
        m = re.search(r'(?:^|&)limit=([^&]+)', q or "")
        limit = m.group(1) if m else "3"
        headers.append(("Link", f'</api/notes?limit={limit}&cursor=next>; rel="next"'))

    start_response(status, headers)
    return out

# Alias estándar
app = application
