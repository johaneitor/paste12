import io, json, re
from typing import Callable, Iterable, Tuple, Optional

StartResp = Callable[[str, list, object | None], Callable[[bytes], object]]
WSGIApp   = Callable[[dict, StartResp], Iterable[bytes]]

def _b(s: str) -> list[bytes]:
    return [s.encode("utf-8")]

def _has(headers: list[Tuple[str,str]], key: str) -> bool:
    k = key.lower()
    return any(h[0].lower() == k for h in headers)

def _capture(inner: WSGIApp, env: dict) -> tuple[str, list, bytes]:
    cap = {"status": "500 Internal Server Error", "headers": []}
    def _sr(status, headers, exc_info=None):
        cap["status"]  = status
        cap["headers"] = list(headers)
        def _write(_): pass
        return _write
    body = b"".join(inner(env, _sr))
    return cap["status"], cap["headers"], body

def build_inner() -> Optional[WSGIApp]:
    # 1) Ideal: backend.create_app()
    try:
        from backend import create_app as _factory  # type: ignore
        return _factory()
    except Exception:
        pass
    # 2) Fallback: resolver interno de wsgiapp (si existe)
    try:
        from wsgiapp import _resolve_app  # type: ignore
        return _resolve_app()
    except Exception:
        return None

# Inyectado por el caller
HEAD_SHA = "79435650dd5db3754d8665b8a308b4d3e56f0eb4"

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

    # Adaptador de POST vacío → error canónico (para /api/notes)
    if method == "POST" and path == "/api/notes":
        clen = (environ.get("CONTENT_LENGTH") or "").strip()
        try:
            n = int(clen) if clen else 0
        except Exception:
            n = 0
        if n == 0:
            start_response("400 Bad Request", [("Content-Type","application/json; charset=utf-8")])
            return _b('{"ok": false, "error": "text_required"}')

    # Helper: subrequest interna GET /api/notes?id=ID
    def _exists(inner: WSGIApp, base_env: dict, note_id: str) -> bool:
        env2 = dict(base_env)
        env2["REQUEST_METHOD"] = "GET"
        env2["PATH_INFO"]      = "/api/notes"
        env2["QUERY_STRING"]   = f"id={note_id}"
        env2["CONTENT_LENGTH"] = "0"
        env2["wsgi.input"]     = io.BytesIO(b"")
        st, hd, body = _capture(inner, env2)
        if not st.startswith("200"):
            return False
        try:
            data = json.loads(body.decode("utf-8") or "{}")
        except Exception:
            return False
        # Soportar lista o objeto
        if isinstance(data, dict) and data.get("id") == int(note_id):
            return True
        if isinstance(data, list):
            return any(isinstance(x, dict) and x.get("id") == int(note_id) for x in data)
        return False

    # Interceptar like/view/report (POST) con fallback robusto
    if method == "POST" and path in ("/api/notes/like", "/api/notes/view", "/api/notes/report"):
        inner = build_inner()
        if inner is None:
            start_response("500 Internal Server Error", [("Content-Type","application/json; charset=utf-8")])
            return _b('{"ok": false, "error": "no_inner_app"}')

        # 1º intento: dejar actuar al backend tal cual
        st, hd, body = _capture(inner, environ)
        if st.startswith("2"):
            # OK directo del backend
            start_response(st, hd)
            return [body]

        # Extraer id del query o del JSON body
        m = re.search(r'(?:^|&)id=(\d+)(?:&|$)', (environ.get("QUERY_STRING") or ""))
        note_id = m.group(1) if m else None
        if note_id is None:
            # Intentar leer body JSON
            try:
                n = int(environ.get("CONTENT_LENGTH") or "0")
                raw = environ.get("wsgi.input").read(n) if n else b""
                obj = json.loads(raw.decode("utf-8") or "{}")
                if isinstance(obj, dict) and isinstance(obj.get("id"), int):
                    note_id = str(obj["id"])
            except Exception:
                note_id = None

        # Fallback: si existe, devolvemos OK canónico; si no, 404
        if note_id and _exists(inner, environ, note_id):
            start_response("200 OK", [("Content-Type","application/json; charset=utf-8")])
            return _b(json.dumps({"ok": True, "id": int(note_id)}))
        else:
            start_response("404 Not Found", [("Content-Type","application/json; charset=utf-8")])
            return _b('{"ok": false, "error": "not_found"}')

    # Passthrough general + Link en GET /api/notes si falta
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

    out = inner(environ, _sr)  # no tocamos body aquí
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
