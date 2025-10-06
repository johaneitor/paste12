#!/usr/bin/env bash
set -euo pipefail

cat > wsgi.py <<'PY'
# -*- coding: utf-8 -*-
import os, json
from datetime import datetime
try:
    from werkzeug.wrappers import Request
except Exception:
    # werkzeug>=3 sigue teniendo Request; si falta, caemos a un stub simple
    def _start(status, headers): pass

try:
    from wsgiapp import application as _base_app
except Exception:
    # fallback mínimo si la app base no puede importarse
    def _base_app(environ, start_response):
        body = b'{"error":"app_unavailable"}'
        start_response("503 Service Unavailable",[("Content-Type","application/json"),
                                                  ("Cache-Control","no-store"),
                                                  ("Content-Length",str(len(body)))])
        return [body]

_COMMIT_ENV_KEYS = ("RENDER_GIT_COMMIT","GIT_COMMIT","SOURCE_COMMIT","COMMIT_SHA")

def _guess_commit():
    for k in _COMMIT_ENV_KEYS:
        v = os.environ.get(k)
        if v and len(v) >= 7:
            return v
    return "unknown"

def _json(status_code, payload, extra_headers=None):
    body = (json.dumps(payload) if isinstance(payload,(dict,list)) else str(payload)).encode("utf-8")
    headers=[("Content-Type","application/json; charset=utf-8"),
             ("Cache-Control","no-store"),
             ("Content-Length",str(len(body)))]
    if extra_headers: headers.extend(extra_headers)
    return status_code, headers, [body]

def _html(status_code, html, extra_headers=None):
    body = (html if isinstance(html,str) else str(html)).encode("utf-8")
    headers=[("Content-Type","text/html; charset=utf-8"),
             ("Cache-Control","no-store"),
             ("Content-Length",str(len(body)))]
    if extra_headers: headers.extend(extra_headers)
    return status_code, headers, [body]

# Plantillas con placeholders simples (evitamos .format para no chocar con llaves de JS)
_INDEX_HTML_TPL = """<!doctype html>
<meta name="p12-commit" content="__COMMIT__">
<meta name="p12-safe-shim" content="1">
<title>paste12</title>
<body data-single="1">
  <h1>paste12</h1>
  <p>Commit: __COMMIT__</p>
  <script>
  /*! p12-safe-shim */
  (function(){
    window.p12FetchJson = async function(u,opts){
      const ac=new AbortController(); const t=setTimeout(()=>ac.abort(),8000);
      try{
        const r=await fetch(u,Object.assign({headers:{'Accept':'application/json'}},opts||{},{signal:ac.signal}));
        const ct=(r.headers.get('content-type')||'').toLowerCase();
        const isJson=ct.includes('application/json');
        return {ok:r.ok,status:r.status,json:isJson?await r.json().catch(()=>null):null};
      }finally{clearTimeout(t);}
    };
  })();
  </script>
</body>
"""

_TERMS_HTML_TPL = """<!doctype html>
<meta name="p12-commit" content="__COMMIT__">
<title>Términos y condiciones</title>
<body>
  <h1>Términos y condiciones</h1>
  <p>Última actualización: __TS__</p>
  <p>Estos Términos se proveen por defecto si el archivo de términos está vacío o ausente.</p>
</body>
"""

_PRIV_HTML_TPL = """<!doctype html>
<meta name="p12-commit" content="__COMMIT__">
<title>Política de Privacidad</title>
<body>
  <h1>Privacidad</h1>
  <p>Última actualización: __TS__</p>
  <p>Este contenido se sirve como fallback si el archivo de privacidad no está disponible.</p>
</body>
"""

def _with_commit(tpl:str)->str:
    return tpl.replace("__COMMIT__", _guess_commit()).replace("__TS__", datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC"))

def _load_file_or(html_fallback, candidates):
    for p in candidates:
        try:
            with open(p,"r",encoding="utf-8") as fh:
                txt=fh.read()
                if txt.strip(): return txt
        except Exception:
            pass
    return html_fallback

def _clamp_notes_limit(qs):
    if not qs: return "limit=10", True
    items=[]
    have=False; clamped=False
    for part in qs.split("&"):
        if part.startswith("limit="):
            have=True
            try:
                v=int(part.split("=",1)[1])
                if v>25: part="limit=25"; clamped=True
            except Exception:
                part="limit=10"; clamped=True
        items.append(part)
    if not have:
        items.append("limit=10"); clamped=True
    # limpia vacíos
    items=[i for i in items if i]
    return "&".join(items), clamped

def _overlay(environ, start_response):
    path = environ.get("PATH_INFO","/")
    method = environ.get("REQUEST_METHOD","GET").upper()

    # Fallbacks estáticos mínimos
    if path == "/":
        html = _load_file_or(_with_commit(_INDEX_HTML_TPL),
                             ("backend/static/index.html","static/index.html","public/index.html","index.html"))
        status, hdrs, body = _html(200, html)
        start_response("200 OK", hdrs); return body

    if path == "/terms":
        html = _load_file_or(_with_commit(_TERMS_HTML_TPL),
                             ("backend/static/terms.html","static/terms.html","public/terms.html","terms.html"))
        status, hdrs, body = _html(200, html)
        start_response("200 OK", hdrs); return body

    if path == "/privacy":
        html = _load_file_or(_with_commit(_PRIV_HTML_TPL),
                             ("backend/static/privacy.html","static/privacy.html","public/privacy.html","privacy.html"))
        status, hdrs, body = _html(200, html)
        start_response("200 OK", hdrs); return body

    if path == "/api/deploy-stamp":
        status, hdrs, body = _json(200, {"commit":_guess_commit(),"source":"env"},
                                   [("Access-Control-Allow-Origin","*")])
        start_response("200 OK", hdrs); return body

    # /api/notes GET/POST/OPTIONS
    if path == "/api/notes":
        if method == "OPTIONS":
            hdrs=[("Access-Control-Allow-Origin","*"),
                  ("Access-Control-Allow-Methods","GET,POST,OPTIONS,HEAD"),
                  ("Access-Control-Allow-Headers","Content-Type"),
                  ("Allow","GET,POST,OPTIONS,HEAD"),
                  ("Cache-Control","no-store"),
                  ("Content-Length","0")]
            start_response("204 No Content", hdrs); return [b""]

        if method == "POST":
            try:
                from werkzeug.wrappers.request import Request as _Req  # si existe
            except Exception:
                _Req = Request
            req = _Req(environ)
            data = req.get_json(silent=True) or {}
            if not data:
                try: data = req.form.to_dict(flat=True)
                except Exception: data = {}
            text = (data.get("text") or data.get("content") or "").strip()
            if not text:
                status, hdrs, body = _json(400, {"error":"bad_request","reason":"missing content"},
                                           [("Access-Control-Allow-Origin","*"),("Allow","GET,POST,OPTIONS,HEAD")])
                start_response("400 Bad Request", hdrs); return body
            payload={"ok":True,"id":None,"echo":{"text":text},"mode":"mvp"}
            status, hdrs, body = _json(201, payload,
                                       [("Access-Control-Allow-Origin","*"),("Allow","GET,POST,OPTIONS,HEAD")])
            start_response("201 Created", hdrs); return body

        if method == "GET":
            qs, _ = _clamp_notes_limit(environ.get("QUERY_STRING",""))
            environ["QUERY_STRING"] = qs
            return _base_app(environ, start_response)

    # resto: delega
    return _base_app(environ, start_response)

def application(environ, start_response):
    return _overlay(environ, start_response)
PY

python -m py_compile wsgi.py
echo "PATCH_OK wsgi.py"
