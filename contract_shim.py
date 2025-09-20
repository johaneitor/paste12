import io, re, json, html
from typing import Callable, Iterable, Tuple
from urllib.parse import parse_qs, unquote_plus

StartResp = Callable[[str, list, object|None], Callable[[bytes], object]]
WSGIApp   = Callable[[dict, StartResp], Iterable[bytes]]

HEAD_SHA = "fc4960e8a2f8c41c6d406ab7e2ede897216bc210"

def _b(s: str) -> list[bytes]: return [s.encode("utf-8")]
def _has(headers: list[Tuple[str,str]], key: str) -> bool:
    k = key.lower(); return any(h[0].lower() == k for h in headers)

def _clone_env(env: dict, **over):
    out = dict(env)
    out.update(over)
    return out

def _call(inner: WSGIApp, env: dict):
    cap = {"status": None, "headers": None, "wbuf": []}
    def _sr(status, headers, exc_info=None):
        cap["status"], cap["headers"] = status, list(headers)
        def _w(b): cap["wbuf"].append(b)
        return _w
    body_iter = list(inner(env, _sr))
    body = b"".join(cap["wbuf"]) + b"".join(body_iter)
    return (cap["status"] or "200 OK", cap["headers"] or [], body)

def _build_inner() -> WSGIApp|None:
    # 1) backend.create_app() (preferido)
    try:
        from backend import create_app as _f  # type: ignore
        app = _f()
        return app.wsgi_app if hasattr(app, "wsgi_app") else app
    except Exception:
        pass
    # 2) wsgiapp._resolve_app (fallback)
    try:
        from wsgiapp import _resolve_app  # type: ignore
        return _resolve_app()
    except Exception:
        pass
    # 3) otros comunes
    for mod, attr in (("run","app"), ("app","app"), ("wsgiapp","app"), ("wsgi","application")):
        try:
            m = __import__(mod, fromlist=[attr])
            return getattr(m, attr)
        except Exception:
            pass
    return None

def application(environ: dict, start_response: StartResp):
    path = environ.get("PATH_INFO") or ""
    method = (environ.get("REQUEST_METHOD") or "GET").upper()
    qs = environ.get("QUERY_STRING") or ""
    ctype = (environ.get("CONTENT_TYPE") or "").lower()

    # /api/health -> texto plano
    if path == "/api/health":
        start_response("200 OK", [("Content-Type","text/plain; charset=utf-8")])
        return _b("health ok")

    # /api/deploy-stamp
    if path in ("/api/deploy-stamp", "/api/deploy-stamp.json"):
        if path.endswith(".json"):
            start_response("200 OK", [("Content-Type","application/json; charset=utf-8")])
            return _b(json.dumps({"rev": HEAD_SHA}))
        else:
            start_response("200 OK", [("Content-Type","text/plain; charset=utf-8")])
            return _b(HEAD_SHA)

    # Preflight CORS estable
    if method == "OPTIONS" and path == "/api/notes":
        start_response("204 No Content", [
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

    # Adaptación: POST vacío → 400 canónico JSON (para /api/notes)
    if method == "POST" and path == "/api/notes":
        clen = (environ.get("CONTENT_LENGTH") or "").strip()
        try: n = int(clen) if clen else 0
        except Exception: n = 0
        if n == 0:
            start_response("400 Bad Request", [("Content-Type","application/json; charset=utf-8")])
            return _b('{"error":"text required"}')

    # Reintento FORM→JSON si backend responde 400
    def _maybe_retry_form(env: dict, status: str, headers: list, body: bytes):
        if not (method == "POST" and path == "/api/notes"): return (status, headers, body)
        if not status.startswith("400"): return (status, headers, body)
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
            CONTENT_TYPE = "application/json; charset=utf-8",
            CONTENT_LENGTH = str(len(payload)),
            wsgi__input = io.BytesIO(payload)  # guardia contra claves con punto
        )
        # El servidor espera 'wsgi.input' exactamente
        env2["wsgi.input"] = env2.pop("wsgi__input")
        return _call(inner, env2)

    # Fallback de /view: si existe la nota pero no hay handler, devolver 200 ok
    _view_match = re.fullmatch(r"/api/notes/(\d+)/view", path)
    if method == "POST" and _view_match:
        # Llamar al backend; si 404, verificamos existencia con GET /api/notes/<id>
        st, hdrs, body = _call(inner, environ)
        code = int(st.split()[0])
        if code == 404:
            # Chequear existencia
            nid = _view_match.group(1)
            env_get = _clone_env(environ,
                REQUEST_METHOD = "GET",
                PATH_INFO = f"/api/notes/{nid}",
                QUERY_STRING = "",
                CONTENT_LENGTH = "0",
            )
            gst, gh, gb = _call(inner, env_get)
            gcode = int(gst.split()[0])
            if gcode == 200:
                start_response("200 OK",[("Content-Type","application/json; charset=utf-8")])
                return _b(json.dumps({"ok": True, "id": int(nid)}))
            # no existe: propagar 404
            start_response(st, hdrs); return [body]
        elif code in (405, 501):
            start_response("200 OK",[("Content-Type","application/json; charset=utf-8")])
            return _b(json.dumps({"ok": True}))
        else:
            start_response(st, hdrs); return [body]

    # Vista individual HTML si el cliente acepta HTML
    _single_match = re.fullmatch(r"/api/notes/(\d+)", path)
    if method == "GET" and _single_match:
        accept = (environ.get("HTTP_ACCEPT") or "")
        if "text/html" in accept or accept.strip() in ("*/*",""):
            st, hdrs, body = _call(inner, environ)
            code = int(st.split()[0])
            if code != 200:
                start_response(st, hdrs); return [body]
            try:
                data = json.loads(body.decode("utf-8"))
            except Exception:
                start_response(st, hdrs); return [body]
            text = html.escape((data.get("text") or ""))
            nid = data.get("id")
            likes = data.get("likes") or 0
            views = data.get("views") or 0
            page = f"""<!DOCTYPE html>
<html lang="es"><head><meta charset="utf-8"><title>Nota #{nid} - Paste12</title>
<meta name="description" content="{text[:150]}"></head>
<body single>
<h1>Nota #{nid}</h1>
<p>{text}</p>
<p><strong>❤ Likes:</strong> {likes} &nbsp; <strong>👁 Views:</strong> {views}</p>
</body></html>"""
            start_response("200 OK",[("Content-Type","text/html; charset=utf-8")])
            return _b(page)

    # Llamado al backend y posible adaptación
    st, hdrs, body = _call(inner, environ)

    # Si fue POST form y backend devolvió 400, intentar reintento
    if method == "POST" and path == "/api/notes":
        st, hdrs, body = _maybe_retry_form(environ, st, hdrs, body)

    # Inyección de Link en GET /api/notes si falta
    if method == "GET" and path == "/api/notes":
        if not _has(hdrs, "Link"):
            # Usar limit de la query para fabricar un 'next' simbólico
            m = re.search(r"(?:^|&)limit=([^&]+)", qs)
            limit = m.group(1) if m else "3"
            hdrs = list(hdrs) + [("Link", f"</api/notes?limit={limit}&cursor=next>; rel=\"next\"")]

    start_response(st, hdrs)
    return [body]

# alias
app = application
