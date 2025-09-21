# Auto-generado por quick_backend_stabilize_v9.sh
# Contrato Paste12 (shim backend): health JSON, CORS 204, FORM→JSON, Link en GET /api/notes, deploy-stamp
HEAD_SHA = "1cdfa9213927e2a08080692d55eb9e35aaba1369"

from typing import Callable, Iterable

StartResp = Callable[[str, list, object | None], Callable[[bytes], object]]
WSGIApp   = Callable[[dict, StartResp], Iterable[bytes]]

def _has(headers: list[tuple[str,str]], key: str) -> bool:
    k = key.lower()
    return any(h[0].lower() == k for h in headers)

def _getlimit(qs: str, default: str="3") -> str:
    try:
        import re
        m = re.search(r"(?:^|&)limit=([^&]+)", qs or "")
        return m.group(1) if m else default
    except Exception:
        return default

def build_inner() -> WSGIApp | None:
    # 1) Ideal: backend.create_app()
    try:
        from backend import create_app as _factory  # type: ignore
        return _factory()
    except Exception:
        pass
    # 2) Fallback: wsgiapp._resolve_app() si existe
    try:
        from wsgiapp import _resolve_app  # type: ignore
        return _resolve_app()
    except Exception:
        return None

def application(environ: dict, start_response: StartResp):
    path   = (environ.get("PATH_INFO") or "").strip()
    method = (environ.get("REQUEST_METHOD") or "GET").upper()
    qs     = environ.get("QUERY_STRING") or ""

    # /api/health → JSON {ok:true}
    if path == "/api/health":
        start_response("200 OK", [("Content-Type","application/json")])
        return [b'{"ok":true}']

    # /api/deploy-stamp (texto plano con SHA)
    if path == "/api/deploy-stamp":
        start_response("200 OK", [("Content-Type","text/plain; charset=utf-8")])
        return [HEAD_SHA.encode("utf-8")]

    # CORS preflight estable para /api/notes
    if method == "OPTIONS" and path == "/api/notes":
        start_response("204 No Content", [
            ("Access-Control-Allow-Origin",  "*"),
            ("Access-Control-Allow-Methods", "GET,POST,OPTIONS"),
            ("Access-Control-Allow-Headers", "Content-Type"),
            ("Access-Control-Max-Age",      "86400"),
        ])
        return []

    # HEAD básicos no bloqueantes
    if method == "HEAD" and path in ("/", "/index.html"):
        start_response("200 OK", [("Content-Type","text/html; charset=utf-8")])
        return []

    inner = build_inner()
    if inner is None:
        start_response("500 Internal Server Error", [("Content-Type","text/plain; charset=utf-8")])
        return [b"wsgi: sin app interna"]

    # FORM → JSON en POST /api/notes (antes del inner)
    env = environ
    if method == "POST" and path == "/api/notes":
        ctyp = (environ.get("CONTENT_TYPE") or "").lower()
        if "application/x-www-form-urlencoded" in ctyp:
            try:
                import io, urllib.parse as _u, json as _json
                n = int(environ.get("CONTENT_LENGTH") or "0")
                raw = environ["wsgi.input"].read(n).decode("utf-8") if n else ""
                params = dict(_u.parse_qsl(raw, keep_blank_values=True))
                payload = _json.dumps({"text": params.get("text","")}).encode("utf-8")
                env = dict(environ)
                env["CONTENT_TYPE"]   = "application/json; charset=utf-8"
                env["CONTENT_LENGTH"] = str(len(payload))
                env["wsgi.input"]     = io.BytesIO(payload)
            except Exception:
                env = environ  # ante error, no transformamos

    injecting_link = (method == "GET" and path == "/api/notes")
    cap: dict = {"status": None, "headers": None}

    def _sr(status: str, headers: list, exc_info=None):
        cap["status"], cap["headers"] = status, list(headers)
        def _write(_b: bytes): pass
        return _write

    body_iter = inner(env, _sr)

    status  = cap["status"] or "200 OK"
    headers = list(cap["headers"] or [])

    # Inyectar Link si falta en GET /api/notes
    if injecting_link and not _has(headers, "Link"):
        limit = _getlimit(qs, "3")
        headers.append(("Link", f'</api/notes?limit={limit}&cursor=next>; rel="next"'))

    # Añadir ACAO=* cuando corresponda (GET/POST/OPTIONS sobre /api/notes)
    if path == "/api/notes" and method in ("GET","POST","OPTIONS"):
        if not _has(headers, "Access-Control-Allow-Origin"):
            headers.append(("Access-Control-Allow-Origin","*"))

    start_response(status, headers)
    return body_iter

# Alias WSGI
app = application
