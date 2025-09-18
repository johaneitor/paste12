import json, re, io
from urllib.parse import unquote_plus

# Embed de HEAD para /api/deploy-stamp (lo reemplazamos más abajo)
HEAD_SHA = "41ce418f05d516e3783442505b51fc40e92319bc"

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
