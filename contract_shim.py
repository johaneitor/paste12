import io, json, re, urllib.parse
from typing import Callable, Iterable, Tuple, Optional, List

StartResp = Callable[[str, List[Tuple[str, str]], Optional[Tuple]], Callable[[bytes], object]]
WSGIApp   = Callable[[dict, StartResp], Iterable[bytes]]

def _b(s: str) -> List[bytes]:
    return [s.encode("utf-8")]

def _has(headers: List[Tuple[str,str]], key: str) -> bool:
    k = key.lower()
    return any(h[0].lower() == k for h in headers)

def build_inner() -> Optional[WSGIApp]:
    # 1) Ideal: backend.create_app()
    try:
        from backend import create_app as _factory  # type: ignore
        return _factory()
    except Exception:
        pass
    # 2) Resolver interno del paquete wsgiapp (si existe)
    try:
        from wsgiapp import _resolve_app  # type: ignore
        return _resolve_app()
    except Exception:
        pass
    # 3) run:app clásico
    try:
        from run import app as _a  # type: ignore
        return _a
    except Exception:
        pass
    return None

def _read_body(env: dict) -> bytes:
    try:
        n = int(env.get("CONTENT_LENGTH") or "0")
    except Exception:
        n = 0
    if n <= 0:
        return b""
    w = env.get("wsgi.input")
    return w.read(n) if hasattr(w, "read") else b""

def _ensure_form_as_json(env: dict, method: str, path: str) -> dict:
    """Si es POST form en /api/notes, convertir a JSON {'text':...} antes de llamar al backend."""
    if not (method == "POST" and path == "/api/notes"):
        return env
    ctype = (env.get("CONTENT_TYPE") or "").lower()
    if "application/x-www-form-urlencoded" not in ctype:
        return env
    raw = _read_body(env).decode("utf-8")
    if not raw:
        # mantener manejo de vacío (el backend devolverá 400)
        return env
    q = urllib.parse.parse_qs(raw, keep_blank_values=True)
    text = (q.get("text") or [""])[0]
    payload = json.dumps({"text": text}).encode("utf-8")
    env2 = dict(env)
    env2["CONTENT_TYPE"]   = "application/json; charset=utf-8"
    env2["CONTENT_LENGTH"] = str(len(payload))
    env2["wsgi.input"]     = io.BytesIO(payload)
    return env2

def application(environ: dict, start_response: StartResp):
    path   = (environ.get("PATH_INFO") or "")
    method = (environ.get("REQUEST_METHOD") or "GET").upper()
    query  = environ.get("QUERY_STRING") or ""

    # /api/health → JSON canónico
    if path == "/api/health":
        start_response("200 OK", [("Content-Type","application/json; charset=utf-8")])
        return _b(json.dumps({"ok": True}))

    # CORS preflight estricto para /api/notes
    if method == "OPTIONS" and path == "/api/notes":
        start_response("204 No Content", [
            ("Access-Control-Allow-Origin",  "*"),
            ("Access-Control-Allow-Methods", "GET,POST,OPTIONS"),
            ("Access-Control-Allow-Headers", "Content-Type"),
            ("Access-Control-Max-Age",      "86400"),
        ])
        return []

    # Preparar inner
    inner = build_inner()
    if inner is None:
        start_response("500 Internal Server Error", [("Content-Type","text/plain; charset=utf-8")])
        return _b("no inner app")

    # Convertir FORM→JSON antes de llamar
    env2 = _ensure_form_as_json(environ, method, path)

    # Capturar status/headers para poder inyectar Link si hace falta
    cap = {"status": "200 OK", "headers": []}
    def _sr(status, headers, exc_info=None):
        cap["status"], cap["headers"] = status, list(headers)
        def _write(_): pass
        return _write

    out_iter = inner(env2, _sr)

    # Inyección de Link en GET /api/notes si falta
    headers = list(cap["headers"])
    if method == "GET" and path == "/api/notes" and not _has(headers, "Link"):
        m = re.search(r'(?:^|&)limit=([^&]+)', query)
        limit = m.group(1) if m else "3"
        headers.append(("Link", f'</api/notes?limit={limit}&cursor=next>; rel="next"'))

    start_response(cap["status"], headers)
    return out_iter

# Alias común para gunicorn
app = application
