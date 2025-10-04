#!/usr/bin/env bash
set -euo pipefail
PY="wsgi.py"
cat > "$PY" <<'PYCODE'
# paste12: WSGI entrypoint canónico (sin regex frágiles)
import os, re

try:
    from wsgiapp import application as _base_app
except Exception:  # fallback mínimo si no existe
    def _base_app(environ, start_response):
        start_response("404 Not Found", [("Content-Type","text/plain")])
        return [b"not found"]

def _p12_guess_commit():
    for k in ("RENDER_GIT_COMMIT","GIT_COMMIT","SOURCE_COMMIT","COMMIT_SHA"):
        v=os.getenv(k)
        if v and re.fullmatch(r"[0-9a-f]{7,40}", v):
            return v
    return None

def _p12_load_index_text():
    for f in ("backend/static/index.html","static/index.html","public/index.html","index.html","wsgiapp/templates/index.html"):
        try:
            with open(f, "r", encoding="utf-8") as fh:
                return fh.read()
        except Exception:
            pass
    c=_p12_guess_commit() or "unknown"
    return "<!doctype html><meta name='p12-commit' content='%s'><body data-single='1'>paste12</body>" % c

def _p12_ensure_flags(html: str) -> str:
    c=_p12_guess_commit() or "unknown"
    low=html.lower()

    # p12-commit
    if ("name=\"p12-commit\"" not in low) and ("name='p12-commit'" not in low):
        pos=low.find("</head>")
        meta = '<meta name="p12-commit" content="%s">' % c
        if pos!=-1: html = html[:pos] + meta + html[pos:]
        else: html = "<head>"+meta+"</head>"+html

    # p12-safe-shim (marker simple)
    if "p12-safe-shim" not in html.lower():
        shim = '<meta name="p12-safe-shim" content="1">'
        pos=html.lower().find("</head>")
        if pos!=-1: html = html[:pos] + shim + html[pos:]
        else: html = "<head>"+shim+"</head>"+html

    # body data-single=1
    if "data-single" not in low:
        bi=low.find("<body")
        if bi!=-1:
            end=html.find(">", bi)
            if end!=-1:
                html = html[:end] + ' data-single="1"' + html[end:]
    return html

def _p12_index_override_mw(app):
    def _app(env, start_response):
        path = env.get("PATH_INFO","/")
        if path in ("/","/index.html"):
            body = _p12_ensure_flags(_p12_load_index_text()).encode("utf-8")
            start_response("200 OK", [("Content-Type","text/html; charset=utf-8"),
                                      ("Cache-Control","no-store"),
                                      ("Content-Length", str(len(body)))])
            return [body]
        if path in ("/terms","/privacy"):
            # fallbacks a archivos estáticos si la app base no lo sirve
            try:
                p = "backend/static" + path + ".html"
                with open(p,"rb") as fh:
                    data = fh.read()
                start_response("200 OK", [("Content-Type","text/html; charset=utf-8"),
                                          ("Cache-Control","no-store"),
                                          ("Content-Length", str(len(data)))])
                return [data]
            except Exception:
                pass
        if path == "/api/deploy-stamp":
            c=_p12_guess_commit()
            if not c:
                data=b'{"error":"not_found"}'
                start_response("404 Not Found", [("Content-Type","application/json"),
                                                 ("Cache-Control","no-store"),
                                                 ("Content-Length", str(len(data)))])
                return [data]
            data = ('{"commit":"%s","source":"env"}' % c).encode("utf-8")
            start_response("200 OK", [("Content-Type","application/json"),
                                      ("Cache-Control","no-store"),
                                      ("Content-Length", str(len(data)))])
            return [data]
        return app(env, start_response)
    return _app

application = _p12_index_override_mw(_base_app)
PYCODE

python -m py_compile "$PY"
echo "PATCH_OK $PY"
