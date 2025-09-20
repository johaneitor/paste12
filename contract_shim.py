import io, json, re
from typing import Callable, Iterable, Tuple, Optional, List, Dict

StartResp = Callable[[str, List[Tuple[str,str]], Optional[Tuple]], Callable[[bytes], object]]
WSGIApp   = Callable[[Dict, StartResp], Iterable[bytes]]

def _b(s: str) -> List[bytes]:
    return [s.encode("utf-8")]

def _has(headers: List[Tuple[str,str]], key: str) -> bool:
    k = key.lower()
    return any(h[0].lower() == k for h in headers)

def build_inner() -> Optional[WSGIApp]:
    # Intento A: backend.create_app()
    try:
        from backend import create_app as _factory  # type: ignore
        return _factory()
    except Exception:
        pass
    # Intento B: wsgiapp._resolve_app()
    try:
        from wsgiapp import _resolve_app  # type: ignore
        return _resolve_app()
    except Exception:
        return None

HEAD_SHA = "a883339ff43e5ad055c5ef9688b3ddcf9eaf7b65"

def _read_body(env: dict) -> bytes:
    try:
        n = int((env.get("CONTENT_LENGTH") or "0").strip() or "0")
    except Exception:
        n = 0
    w = env.get("wsgi.input")
    try:
        return w.read(n) if (w is not None and n > 0) else b""
    except Exception:
        return b""

def _call(inner: WSGIApp, env: dict):
    cap = {"status": None, "headers": None, "buf": []}
    def _sr(status, headers, exc_info=None):
        cap["status"], cap["headers"] = status, list(headers)
        def _write(b):
            cap["buf"].append(b)
        return _write
    out_iter = inner(env, _sr)
    # materializar por si necesitamos tocar body/headers (no copiamos si ya hay buf)
    body: List[bytes] = cap["buf"] or list(out_iter)
    status: str = cap["status"] or "200 OK"
    headers: List[Tuple[str,str]] = cap["headers"] or []
    return status, headers, body

def application(environ: dict, start_response: StartResp):
    path   = (environ.get("PATH_INFO") or "")
    method = (environ.get("REQUEST_METHOD") or "GET").upper()
    q      = environ.get("QUERY_STRING") or ""

    # --- health JSON ---
    if path == "/api/health":
        start_response("200 OK", [("Content-Type","application/json; charset=utf-8")])
        return _b(json.dumps({"ok": True}))

    # --- deploy-stamp (txt/json) ---
    if path == "/api/deploy-stamp" or path == "/api/deploy-stamp.json":
        if path.endswith(".json"):
            start_response("200 OK", [("Content-Type","application/json; charset=utf-8")])
            return _b(json.dumps({"rev": HEAD_SHA}))
        else:
            start_response("200 OK", [("Content-Type","text/plain; charset=utf-8")])
            return _b(HEAD_SHA)

    # --- CORS preflight estable ---
    if method == "OPTIONS" and path == "/api/notes":
        start_response("204 No Content", [
            ("Access-Control-Allow-Origin",  "*"),
            ("Access-Control-Allow-Methods", "GET,POST,OPTIONS"),
            ("Access-Control-Allow-Headers", "Content-Type"),
            ("Access-Control-Max-Age",      "86400"),
        ])
        return []

    # --- HEAD básico para / e /index.html ---
    if method == "HEAD" and path in ("/", "/index.html"):
        start_response("200 OK", [("Content-Type","text/html; charset=utf-8")])
        return []

    # --- POST vacío canonical error ---
    if method == "POST" and path == "/api/notes":
        raw = _read_body(environ)
        if not raw:
            start_response("400 Bad Request", [("Content-Type","application/json; charset=utf-8")])
            return _b(json.dumps({"error": "text required"}))

    inner = build_inner()
    if inner is None:
        start_response("500 Internal Server Error", [("Content-Type","text/plain; charset=utf-8")])
        return _b("wsgi: no inner app")

    # --- FORM → JSON para POST /api/notes ---
    if method == "POST" and path == "/api/notes":
        ctyp = (environ.get("CONTENT_TYPE") or "").lower()
        if "application/x-www-form-urlencoded" in ctyp:
            raw = _read_body(environ).decode("utf-8", "ignore")
            m = re.search(r'(?:^|&)text=([^&]+)', raw)
            if m:
                import urllib.parse as _u
                text = _u.unquote_plus(m.group(1))
                payload = json.dumps({"text": text}).encode("utf-8")
                env2 = dict(environ)
                env2["CONTENT_TYPE"]   = "application/json; charset=utf-8"
                env2["CONTENT_LENGTH"] = str(len(payload))
                env2["HTTP_ACCEPT"]    = "application/json"
                env2["wsgi.input"]     = io.BytesIO(payload)
                status, headers, body = _call(inner, env2)
                start_response(status, headers)
                return body
            else:
                # si no hay text=, dejamos que el backend responda
                pass
        # si no era form, al menos forzamos Accept en JSON
        if not environ.get("HTTP_ACCEPT"):
            environ = dict(environ)
            environ["HTTP_ACCEPT"] = "application/json"

    # --- Llamada principal ---
    status, headers, body = _call(inner, environ)

    # --- Inyección Link en GET /api/notes ---
    if method == "GET" and path == "/api/notes" and not _has(headers, "Link"):
        m = re.search(r'(?:^|&)limit=([^&]+)', q or "")
        limit = (m.group(1) if m else "3")
        headers.append(("Link", f'</api/notes?limit={limit}&cursor=next>; rel="next"'))

    start_response(status, headers)
    return body

# alias gunicorn
app = application
