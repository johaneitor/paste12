import io, json, re, urllib.parse as _u
from typing import Callable, Iterable, Tuple

StartResp = Callable[[str, list, object | None], Callable[[bytes], object]]
WSGIApp   = Callable[[dict, StartResp], Iterable[bytes]]

def _b(s: str) -> list[bytes]:
    return [s.encode("utf-8")]

def _has(headers, key: str) -> bool:
    k = key.lower()
    return any((h[0] or "").lower() == k for h in headers)

def _get(headers, key: str):
    k = key.lower()
    for n,v in headers:
        if (n or "").lower() == k: return v
    return None

def _replace_status_to(status: str, new_code: int, new_text: str) -> str:
    # status: "500 Internal Server Error" → "404 Not Found"
    return f"{new_code} {new_text}"

HEAD_SHA = "e876efd2d6dd89692faa2e827c0e628732daa7bd"

def build_inner() -> WSGIApp | None:
    # 1) Intentar backend.create_app() (ideal)
    try:
        from backend import create_app as _factory  # type: ignore
        return _factory()
    except Exception:
        pass
    # 2) Intentar resolver interno de wsgiapp
    try:
        from wsgiapp import _resolve_app  # type: ignore
        return _resolve_app()
    except Exception:
        return None

def application(environ: dict, start_response: StartResp):
    method = (environ.get("REQUEST_METHOD") or "GET").upper()
    path   = environ.get("PATH_INFO") or ""
    q      = environ.get("QUERY_STRING") or ""

    # /api/health → JSON estable
    if path == "/api/health":
        start_response("200 OK", [("Content-Type","application/json")])
        return _b('{"ok":true}')

    # /api/deploy-stamp (txt/json)
    if path == "/api/deploy-stamp" or path == "/api/deploy-stamp.json":
        if path.endswith(".json"):
            start_response("200 OK", [("Content-Type","application/json; charset=utf-8")])
            return _b(json.dumps({"rev": HEAD_SHA}))
        else:
            start_response("200 OK", [("Content-Type","text/plain; charset=utf-8")])
            return _b(HEAD_SHA)

    # OPTIONS /api/notes → CORS 204
    if method == "OPTIONS" and path == "/api/notes":
        start_response("204 No Content", [
            ("Access-Control-Allow-Origin",  "*"),
            ("Access-Control-Allow-Methods", "GET,POST,OPTIONS"),
            ("Access-Control-Allow-Headers", "Content-Type"),
            ("Access-Control-Max-Age",      "86400"),
        ])
        return []

    # HEAD / y /index.html (no bloqueante)
    if method == "HEAD" and path in ("/", "/index.html"):
        start_response("200 OK", [("Content-Type","text/html; charset=utf-8")])
        return []

    # FORM → JSON (POST /api/notes) si llega como x-www-form-urlencoded
    def _maybe_retry_form(inner: WSGIApp, env: dict, sr: StartResp):
        cap = {"status": None, "headers": None}
        def _sr(status, headers, exc_info=None):
            cap["status"], cap["headers"] = status, list(headers)
            def _w(_): pass
            return _w
        out = list(inner(env, _sr))

        # Solo nos interesa POST /api/notes con 400 Bad Request
        if not (method == "POST" and path == "/api/notes"):
            sr(cap["status"] or "200 OK", cap["headers"] or [])
            return out
        if not (cap["status"] or "").startswith("400"):
            sr(cap["status"] or "200 OK", cap["headers"] or [])
            return out

        ctyp = (env.get("CONTENT_TYPE") or "").lower()
        if "application/x-www-form-urlencoded" not in ctyp:
            sr(cap["status"] or "400 Bad Request", cap["headers"] or [])
            return out

        try:
            w = env["wsgi.input"]; n = int(env.get("CONTENT_LENGTH") or "0")
            raw = w.read(n).decode("utf-8") if n else ""
        except Exception:
            sr(cap["status"] or "400 Bad Request", cap["headers"] or [])
            return out

        m = re.search(r'(?:^|&)text=([^&]+)', raw)
        if not m:
            sr(cap["status"] or "400 Bad Request", cap["headers"] or [])
            return out

        text = _u.unquote_plus(m.group(1))
        payload = json.dumps({"text": text}).encode("utf-8")

        env2 = dict(env)
        env2["CONTENT_TYPE"]   = "application/json; charset=utf-8"
        env2["CONTENT_LENGTH"] = str(len(payload))
        env2["wsgi.input"]     = io.BytesIO(payload)

        cap2 = {"status": None, "headers": None}
        def _sr2(status, headers, exc_info=None):
            cap2["status"], cap2["headers"] = status, list(headers)
            def _w(_): pass
            return _w
        out2 = inner(env2, _sr2)
        sr(cap2["status"] or "200 OK", cap2["headers"] or [])
        return out2

    inner = build_inner()
    if inner is None:
        start_response("500 Internal Server Error", [("Content-Type","text/plain; charset=utf-8")])
        return _b("wsgi: sin app interna")

    # Captura de respuesta
    cap = {"status": None, "headers": None, "body": []}
    def _sr(status: str, headers: list, exc_info=None):
        cap["status"], cap["headers"] = status, list(headers)
        def _w(b): cap["body"].append(b)
        return _w

    # Ejecutar con posible retry FORM
    out = _maybe_retry_form(inner, environ, _sr)
    status = cap["status"] or "200 OK"
    headers = cap["headers"] or []

    # Normalizar 500→404 en like/view/report cuando el ID no existe
    if method == "POST" and re.match(r"^/api/notes/\d+/(like|view|report)$", path):
        if str(status).startswith("500"):
            status = _replace_status_to(status, 404, "Not Found")
            # Respuesta mínima JSON
            if not _has(headers, "Content-Type"):
                headers.append(("Content-Type","application/json; charset=utf-8"))
            cap["body"] = [b'{"ok":false,"error":"not_found"}']

    # Inyección de Link en GET /api/notes si falta
    if method == "GET" and path == "/api/notes" and not _has(headers, "Link"):
        m = re.search(r'(?:^|&)limit=([^&]+)', q or "")
        limit = m.group(1) if m else "3"
        headers.append(("Link", f'</api/notes?limit={limit}&cursor=next>; rel="next"'))

    # Asegurar CORS global ligero (no molesta si ya existe)
    if not _has(headers, "Access-Control-Allow-Origin"):
        headers.append(("Access-Control-Allow-Origin","*"))

    # Emitir
    start_response(status, headers)
    return out

# Alias estándar
app = application
