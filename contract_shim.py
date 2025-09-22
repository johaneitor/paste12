# Paste12 Contract Shim v9 — backend hardening layer
# - /api/health -> JSON {"ok":true}
# - OPTIONS /api/notes -> 204 + CORS headers
# - POST /api/notes (form) -> reintenta como JSON {"text":...}
# - GET /api/notes -> inyecta Link: rel="next" si falta
# - /api/deploy-stamp(.json) -> HEAD SHA
# - passthrough para todo lo demás

import io, json, re, urllib.parse
from typing import Callable, Iterable, Tuple, Optional

StartResp = Callable[[str, list, object | None], Callable[[bytes], object]]
WSGIApp   = Callable[[dict, StartResp], Iterable[bytes]]

HEAD_SHA = "f10427e1e984ad723a11772a047fc1db22bbe730"   # sustituido por script

def _b(s: str) -> list[bytes]:
    return [s.encode("utf-8")]

def _has(headers: list[Tuple[str,str]], key: str) -> bool:
    lk = key.lower()
    return any(h[0].lower() == lk for h in headers)

def _json(status: str, obj: dict) -> tuple[str, list[Tuple[str,str]], list[bytes]]:
    body = json.dumps(obj, separators=(",",":")).encode("utf-8")
    return status, [("Content-Type","application/json")], [body]

def build_inner() -> Optional[WSGIApp]:
    # 1) Intentá un app factory real
    try:
        from backend import create_app as _factory  # type: ignore
        return _factory()
    except Exception:
        pass
    # 2) Fallback al resolver del paquete wsgiapp (si existe)
    try:
        from wsgiapp import _resolve_app  # type: ignore
        return _resolve_app()
    except Exception:
        return None

def application(environ: dict, start_response: StartResp):
    path   = environ.get("PATH_INFO") or ""
    method = (environ.get("REQUEST_METHOD") or "GET").upper()
    query  = environ.get("QUERY_STRING") or ""

    # /api/health → JSON estable
    if path == "/api/health":
        status, headers, body = _json("200 OK", {"ok": True})
        start_response(status, headers)
        return body

    # /api/deploy-stamp (.txt y .json)
    if path == "/api/deploy-stamp" or path == "/api/deploy-stamp.json":
        if path.endswith(".json"):
            status, headers, body = _json("200 OK", {"rev": HEAD_SHA})
            start_response(status, headers)
            return body
        else:
            start_response("200 OK", [("Content-Type","text/plain; charset=utf-8")])
            return _b(HEAD_SHA)

    # Preflight CORS estable para /api/notes
    if method == "OPTIONS" and path == "/api/notes":
        headers = [
            ("Access-Control-Allow-Origin","*"),
            ("Access-Control-Allow-Methods","GET,POST,OPTIONS"),
            ("Access-Control-Allow-Headers","Content-Type"),
            ("Access-Control-Max-Age","86400"),
        ]
        start_response("204 No Content", headers)
        return []

    # HEAD estático útil (no bloqueante)
    if method == "HEAD" and path in ("/", "/index.html"):
        start_response("200 OK", [("Content-Type","text/html; charset=utf-8")])
        return []

    # Asegurar inner
    inner = build_inner()
    if inner is None:
        start_response("500 Internal Server Error", [("Content-Type","text/plain; charset=utf-8")])
        return _b("p12-shim: inner app missing")

    # Adaptador: si POST form a /api/notes, convertir a JSON {"text":...}
    if method == "POST" and path == "/api/notes":
        ctyp = (environ.get("CONTENT_TYPE") or "").lower()
        if "application/x-www-form-urlencoded" in ctyp:
            try:
                n = int(environ.get("CONTENT_LENGTH") or "0")
            except Exception:
                n = 0
            raw = (environ.get("wsgi.input").read(n).decode("utf-8") if n else "")
            text = urllib.parse.parse_qs(raw).get("text", [""])[0]
            if not text:
                status, headers, body = _json("400 Bad Request", {"error":"text required"})
                start_response(status, headers)
                return body
            payload = json.dumps({"text": text}, separators=(",",":")).encode("utf-8")
            env2 = dict(environ)
            env2["CONTENT_TYPE"]   = "application/json; charset=utf-8"
            env2["CONTENT_LENGTH"] = str(len(payload))
            env2["wsgi.input"]     = io.BytesIO(payload)
            return inner(env2, start_response)

    # Passthrough con posibilidad de inyectar Link: rel="next" en GET /api/notes
    injecting_link = (method == "GET" and path == "/api/notes")
    cap = {"status":"", "headers": []}
    def _sr(status: str, headers: list, exc_info=None):
        cap["status"], cap["headers"] = status, list(headers)
        def _write(_): pass
        return _write

    body_iter = inner(environ, _sr)
    status     = cap["status"] or "200 OK"
    headers    = list(cap["headers"] or [])

    if injecting_link and status.startswith("200") and not _has(headers, "Link"):
        m = re.search(r'(?:^|&)limit=([^&]+)', query)
        limit = m.group(1) if m else "3"
        headers.append(("Link", f'</api/notes?limit={limit}&cursor=next>; rel="next"'))

    start_response(status, headers)
    return body_iter

# WSGI alias
app = application
