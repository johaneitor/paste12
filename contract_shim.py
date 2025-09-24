# -*- coding: utf-8 -*-
"""
Paste12 backend contract shim v13:
- Preflight CORS: responde 204 en OPTIONS /api/* + CORS headers
- CORS headers en todas las respuestas /api/*
- POST FORM -> JSON en /api/notes
- Link: <...>; rel="next" en GET /api/notes
- Exporta `application` para gunicorn (wsgi:application)
"""
from io import BytesIO
import json, sys
from typing import Iterable, List, Tuple
from urllib.parse import parse_qs, urlencode

# ===== localizar app real =====
def _fail_app(msg: str):
    def _app(environ, start_response):
        start_response("500 Internal Server Error", [("Content-Type","text/plain; charset=utf-8")])
        return [("Paste12 backend shim start error: " + msg).encode("utf-8")]
    return _app

def _import_real_app():
    try:
        # export canónico
        from wsgiapp import application as _app
        return _app
    except Exception as e1:
        try:
            from wsgiapp import app as _app
            return _app
        except Exception as e2:
            try:
                from app import app as _app
                return _app
            except Exception as e3:
                return _fail_app(f"cannot import real app: {e1!r} | {e2!r} | {e3!r}")

_real_app = _import_real_app()

# ===== util =====
def _set_header(headers: List[Tuple[str,str]], name: str, value: str):
    lname = name.lower()
    out: List[Tuple[str,str]] = []
    replaced = False
    for k,v in headers:
        if k.lower() == lname:
            if not replaced:
                out.append((name, value))
                replaced = True
        else:
            out.append((k, v))
    if not replaced:
        out.append((name, value))
    return out

def _cors_headers(headers: List[Tuple[str,str]]):
    headers = _set_header(headers, "Access-Control-Allow-Origin",  "*")
    headers = _set_header(headers, "Access-Control-Allow-Methods", "GET, POST, HEAD, OPTIONS")
    headers = _set_header(headers, "Access-Control-Allow-Headers", "Content-Type")
    headers = _set_header(headers, "Access-Control-Max-Age",       "86400")
    return headers

def _wsgi_url(environ) -> str:
    scheme = environ.get("wsgi.url_scheme","http")
    host   = environ.get("HTTP_HOST") or environ.get("SERVER_NAME","localhost")
    path   = environ.get("PATH_INFO","/")
    qs     = environ.get("QUERY_STRING","")
    return f"{scheme}://{host}{path}" + (f"?{qs}" if qs else "")

# ===== middleware =====
def _shim_app(app):
    def _app(environ, start_response):
        method = (environ.get("REQUEST_METHOD") or "GET").upper()
        path   = environ.get("PATH_INFO") or "/"

        # 1) Preflight CORS en /api/*
        if method == "OPTIONS" and path.startswith("/api/"):
            h = []
            h = _cors_headers(h)
            start_response("204 No Content", h)
            return []

        # 2) Transformar POST FORM -> JSON en /api/notes
        if method == "POST" and path == "/api/notes":
            ctype = (environ.get("CONTENT_TYPE") or "").split(";",1)[0].strip().lower()
            if ctype in ("application/x-www-form-urlencoded","multipart/form-data"):
                try:
                    length = int(environ.get("CONTENT_LENGTH") or "0")
                except ValueError:
                    length = 0
                raw = environ.get("wsgi.input").read(length) if length > 0 else b""
                params = parse_qs(raw.decode("utf-8", "replace"), keep_blank_values=True)
                text = (params.get("text") or [""])[0]
                payload = json.dumps({"text": text}).encode("utf-8")
                environ["wsgi.input"]    = BytesIO(payload)
                environ["CONTENT_LENGTH"] = str(len(payload))
                environ["CONTENT_TYPE"]   = "application/json"

        captured = {"status": None, "headers": None, "exc": None}
        def _sr(status, headers, exc_info=None):
            # CORS para todas las respuestas /api/*
            if path.startswith("/api/"):
                headers = _cors_headers(list(headers))
            captured["status"]  = status
            captured["headers"] = headers
            captured["exc"]     = exc_info
            # devolvemos no-op write callable
            return lambda _b: None

        iterable = app(environ, _sr)
        body_chunks: List[bytes] = []
        try:
            for chunk in iterable:
                body_chunks.append(chunk)
        finally:
            if hasattr(iterable, "close"):
                try: iterable.close()
                except Exception: pass

        status  = captured["status"] or "200 OK"
        headers: List[Tuple[str,str]] = list(captured["headers"] or [])
        body = b"".join(body_chunks)

        # 3) Link rel=next en GET /api/notes (si 200 + JSON)
        if method == "GET" and path == "/api/notes" and status.startswith("200"):
            ctype_hdr = next((v for (k,v) in headers if k.lower()=="content-type"), "")
            if "application/json" in (ctype_hdr or ""):
                try:
                    data = json.loads(body.decode("utf-8"))
                except Exception:
                    data = []
                ids = []
                if isinstance(data, list):
                    for n in data:
                        if isinstance(n, dict) and "id" in n:
                            ids.append(n["id"])
                # construir next con before_id si hay ids; mantener otros qs (p.ej., limit)
                qs = parse_qs(environ.get("QUERY_STRING",""), keep_blank_values=True)
                flat_qs = {k: (v[-1] if v else "") for k,v in qs.items()}
                if ids:
                    flat_qs["before_id"] = str(min(ids))
                base = _wsgi_url({**environ, "QUERY_STRING": ""})
                next_qs = urlencode(flat_qs)
                next_url = base + (("?" + next_qs) if next_qs else "")
                headers = _set_header(headers, "Link", f'<{next_url}>; rel="next"')

        start_response(status, headers, captured["exc"])
        return [body]
    return _app

_orig_app = _orig_app = _orig_app = _orig_app = _orig_app = _orig_app = _orig_app = application = _shim_app(_real_app)
application = _HeadDropMiddleware(_orig_app)
application = _HeadDropMiddleware(_orig_app)
application = _HeadDropMiddleware(_orig_app)
application = _HeadDropMiddleware(_orig_app)
application = _HeadDropMiddleware(_orig_app)
application = _HeadDropMiddleware(_orig_app)
application = _HeadDropMiddleware(_orig_app)
app = application  # alias opcional

# == P12: HTML inject middleware (views + AdSense) ==
class _P12HtmlInjectMiddleware:
    ADS = '<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=ca-pub-9479870293204581" crossorigin="anonymous"></script>'
    VIEWS_BLOCK = (
        '<div id="p12-stats" class="stats">'
        '<span class="views" data-views="0">👁️ <b>0</b></span>'
        '<span class="likes" data-likes="0">❤️ <b>0</b></span>'
        '<span class="reports" data-reports="0">🚩 <b>0</b></span>'
        '</div>'
    )

    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        captured = {}
        body_parts = []

        def _sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers)
            captured["exc_info"] = exc_info
            # devolvemos un "write" que acumula
            return body_parts.append

        app_iter = self.app(environ, _sr)
        try:
            for chunk in app_iter:
                body_parts.append(chunk)
        finally:
            if hasattr(app_iter, "close"):
                app_iter.close()

        body = b"".join(body_parts)

        # Detección de Content-Type
        ct = ""
        for k, v in captured.get("headers", []):
            if k.lower() == "content-type":
                ct = v or ""
                break

        # Inyección sólo si es HTML
        if "text/html" in (ct or "").lower() and body:
            try:
                html = body.decode("utf-8", "ignore")

                # Asegurar AdSense en <head>
                if "pagead/js/adsbygoogle.js?client=" not in html:
                    if "</head>" in html:
                        html = html.replace("</head>", self.ADS + "\n</head>", 1)

                # Asegurar .views (bloque completo si no está)
                if 'class="views"' not in html:
                    if "</body>" in html:
                        html = html.replace("</body>", self.VIEWS_BLOCK + "\n</body>", 1)
                    else:
                        html = html + self.VIEWS_BLOCK

                body = html.encode("utf-8", "ignore")

                # Ajustar Content-Length
                new_headers = []
                for k, v in captured["headers"]:
                    if k.lower() != "content-length":
                        new_headers.append((k, v))
                new_headers.append(("Content-Length", str(len(body))))
                captured["headers"] = new_headers
            except Exception:
                pass  # si algo falla, servimos tal cual

        start_response(captured["status"], captured["headers"], captured["exc_info"])
        return [body]

# Envolver aplicación WSGI si existe 'application' o 'app'
try:
    _exists = application  # noqa: F821
    application = _P12HtmlInjectMiddleware(application)  # type: ignore
except NameError:
    try:
        _exists = app  # noqa: F821
        try:
            # Flask: encadenar sobre wsgi_app
            app.wsgi_app = _P12HtmlInjectMiddleware(app.wsgi_app)  # type: ignore
            application = app  # export canónico
        except Exception:
            # fallback: envolver app directamente
            application = _P12HtmlInjectMiddleware(app)  # type: ignore
    except NameError:
        # No pudimos detectar el objeto WSGI; se mantendrá sin wrap
        pass

# [p12-legal-mw-v1] —— Legal pages WSGI middleware (terms/privacy) + AdSense head
import os, re
from pathlib import Path

# Cliente AdSense (se sobreescribe desde script)
P12_ADSENSE_CLIENT = "ca-pub-9479870293204581"

_P12_AD_TAG = ('<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js'
               '?client={{CID}}" crossorigin="anonymous"></script>').replace("{{CID}}", P12_ADSENSE_CLIENT)

def _p12_has_head(html): 
    return bool(re.search(r'<head[^>]*>', html, re.I))

def _p12_ensure_head_with_adsense(html):
    s = html
    if not _p12_has_head(s):
        # envolver en documento mínimo
        body = s if '<body' in s.lower() else ('<body>' + s + '</body>')
        s = ('<!doctype html>\n<html lang="es"><head><meta charset="utf-8"/>'
             + _P12_AD_TAG + '</head>' + body + '</html>')
    else:
        # asegurar el script AdSense antes de </head>
        if 'pagead2.googlesyndication.com/pagead/js/adsbygoogle.js' not in s:
            s = re.sub(r'</head>', _P12_AD_TAG + '\n</head>', s, flags=re.I)
    return s

def _p12_load_file_or_default(name, title):
    fp = Path("frontend")/name
    if fp.exists():
        try:
            s = fp.read_text("utf-8", errors="replace")
        except Exception:
            s = f"<!doctype html><meta charset=utf-8><title>{title}</title><h1>{title}</h1><p>(contenido mínimo)</p>"
    else:
        s = f"<!doctype html><meta charset=utf-8><title>{title}</title><h1>{title}</h1><p>(contenido mínimo)</p>"
    # stats mínimos (por coherencia visual)
    if 'id="p12-stats"' not in s:
        s += '\n<div id="p12-stats" class="stats"><span class="views" data-views="0">👁️ <b>0</b></span><span class="likes" data-likes="0">❤️ <b>0</b></span><span class="reports" data-reports="0">🚩 <b>0</b></span></div>\n'
    return _p12_ensure_head_with_adsense(s)

def _p12_resp(start_response, body, status="200 OK", ctype="text/html; charset=utf-8"):
    if isinstance(body, str): body = body.encode("utf-8")
    start_response(status, [("Content-Type", ctype), ("Cache-Control","no-cache")])
    return [body]

def _p12_legal_mw(app):
    TERMS = _p12_load_file_or_default("terms.html", "Términos y Condiciones")
    PRIV  = _p12_load_file_or_default("privacy.html", "Política de Privacidad")
    def _mw(environ, start_response):
        try:
            path = environ.get("PATH_INFO","") or ""
            if path.rstrip("/") == "/terms":
                return _p12_resp(start_response, TERMS)
            if path.rstrip("/") == "/privacy":
                return _p12_resp(start_response, PRIV)
        except Exception:
            # en caso de error, seguir al app principal
            pass
        return app(environ, start_response)
    return _mw

# envolver 'application' si existe
try:
    application  # noqa
    application = _p12_legal_mw(application)
except NameError:
    pass


# == Health bypass (no DB, no framework) ==
class _HealthBypassMiddleware:
    def __init__(self, app):
        self.app = app
    def __call__(self, environ, start_response):
        path  = environ.get('PATH_INFO','')
        meth  = environ.get('REQUEST_METHOD','GET').upper()
        if path in ('/api/health','/healthz') and meth in ('GET','HEAD'):
            body = b'{"ok":true}\n'
            headers=[('Content-Type','application/json'),
                     ('Content-Length', str(len(body)))]
            start_response('200 OK', headers)
            return [] if meth=='HEAD' else [body]
        return self.app(environ, start_response)


# === Paste12: unify WSGI wrappers (idempotent) ===
try:
    _p12_base_app = application
except NameError:
    try:
        _p12_base_app = app
    except NameError:
        _p12_base_app = None

if _p12_base_app is not None:
    # Siempre aplicar HealthBypass por dentro
    _p12_wrapped = _HealthBypassMiddleware(_p12_base_app)
    # Si existe HeadDrop, volver a envolver por fuera; si no, usar el envuelto base
    try:
        _ = _HeadDropMiddleware
        application = _HeadDropMiddleware(_p12_wrapped)
    except NameError:
        application = _p12_wrapped



# == HEAD drop-in middleware (idempotente) ==
class _HeadDropMiddleware:
    def __init__(self, app):
        self.app = app
    def __call__(self, environ, start_response):
        method = environ.get('REQUEST_METHOD','GET').upper()
        if method == 'HEAD':
            # Finge GET para construir headers, descarta cuerpo
            environ['REQUEST_METHOD'] = 'GET'
            body_chunks = []
            def _sr(status, headers, exc_info=None):
                # devolvemos mismo status/headers
                start_response(status, headers, exc_info)
                return lambda x: None
            result = self.app(environ, _sr)
            # Consumimos el iterable sin devolver cuerpo
            try:
                for _ in result:
                    pass
            finally:
                if hasattr(result, 'close'):
                    result.close()
            return []
        return self.app(environ, start_response)


class HtmlNoCacheMiddleware:
    def __init__(self, app):
        self.app = app
    def __call__(self, environ, start_response):
        headers_holder = []
        def sr(status, headers, exc_info=None):
            headers_holder[:] = headers
            return start_response(status, headers, exc_info)
        body_iter = self.app(environ, sr)

        # content-type puede venir en headers_holder
        ct = None
        for k,v in headers_holder:
            if k.lower()=="content-type":
                ct=v; break
        is_html = ct and ("text/html" in ct.lower())
        if is_html:
            # forzar revalidación de HTML
            new=[]
            have_cc=False
            for k,v in headers_holder:
                if k.lower()=="cache-control":
                    have_cc=True
                    new.append((k,"no-cache, must-revalidate"))
                else:
                    new.append((k,v))
            if not have_cc:
                new.append(("Cache-Control","no-cache, must-revalidate"))
            headers_holder[:] = new
        return body_iter
