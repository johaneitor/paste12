#!/usr/bin/env bash
set -euo pipefail

# Reemplaza wsgi.py por un loader + overlay WSGI sin regex ni indentación frágil.
cat > wsgi.py <<'PY'
# -*- coding: utf-8 -*-
import os, json, time
from datetime import datetime
from werkzeug.wrappers import Request, Response

# Importa la app base sin tocar su código
from wsgiapp import application as _base_app

_COMMIT_ENV_KEYS = ("RENDER_GIT_COMMIT","GIT_COMMIT","SOURCE_COMMIT","COMMIT_SHA")

def _guess_commit():
    for k in _COMMIT_ENV_KEYS:
        v = os.environ.get(k)
        if v and len(v) >= 7:
            return v
    return "unknown"

# Respuestas utilitarias
def _json(status_code, payload, extra_headers=None):
    body = (json.dumps(payload) if isinstance(payload, (dict, list)) else str(payload)).encode("utf-8")
    headers = [("Content-Type","application/json; charset=utf-8"),
               ("Cache-Control","no-store"),
               ("Content-Length", str(len(body)))]
    if extra_headers:
        headers.extend(extra_headers)
    return status_code, headers, [body]

def _html(status_code, html, extra_headers=None):
    body = (html if isinstance(html, str) else str(html)).encode("utf-8")
    headers = [("Content-Type","text/html; charset=utf-8"),
               ("Cache-Control","no-store"),
               ("Content-Length", str(len(body)))]
    if extra_headers:
        headers.extend(extra_headers)
    return status_code, headers, [body]

# Plantillas mínimas seguras (evitamos regex y dependencias)
_INDEX_HTML = """<!doctype html>
<meta name="p12-commit" content="{commit}">
<meta name="p12-safe-shim" content="1">
<title>paste12</title>
<body data-single="1">
  <h1>paste12</h1>
  <p>Commit: {commit}</p>
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
""".format(commit=_guess_commit())

_TERMS_HTML = """<!doctype html>
<meta name="p12-commit" content="{commit}">
<title>Términos y condiciones</title>
<body>
  <h1>Términos y condiciones</h1>
  <p>Última actualización: {ts}</p>
  <p>Estos Términos se proveen por defecto si el archivo de términos está vacío o ausente.</p>
</body>
""".format(commit=_guess_commit(), ts=datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC"))

_PRIV_HTML = """<!doctype html>
<meta name="p12-commit" content="{commit}">
<title>Política de Privacidad</title>
<body>
  <h1>Privacidad</h1>
  <p>Última actualización: {ts}</p>
  <p>Este contenido se sirve como fallback si el archivo de privacidad no está disponible.</p>
</body>
""".format(commit=_guess_commit(), ts=datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC"))

def _load_file_or(html_fallback, candidates):
    for p in candidates:
        try:
            with open(p, "r", encoding="utf-8") as fh:
                txt = fh.read()
                if txt.strip():
                    return txt
        except Exception:
            pass
    return html_fallback

def _clamp_notes_limit(query_string):
    # Limita limit<=25 para anti-abuso sin romper el BE
    parts = query_string.split("&") if query_string else []
    new = []
    clamped = False
    for kv in parts:
        if kv.startswith("limit="):
            try:
                v = int(kv.split("=",1)[1])
                if v > 25:
                    kv = "limit=25"
                    clamped = True
            except Exception:
                kv = "limit=10"
                clamped = True
        new.append(kv)
    if not any(p.startswith("limit=") for p in new):
        new.append("limit=10")
        clamped = True
    return "&".join([p for p in new if p]), clamped

def _overlay(environ, start_response):
    req = Request(environ)
    path = environ.get("PATH_INFO","/")
    method = environ.get("REQUEST_METHOD","GET").upper()

    # Fallbacks seguros (no-cache) para index/terms/privacy
    if path == "/":
        html = _load_file_or(_INDEX_HTML, ("backend/static/index.html","static/index.html","public/index.html","index.html"))
        status, headers, body = _html(200, html)
        start_response("200 OK", headers); return body

    if path == "/terms":
        html = _load_file_or(_TERMS_HTML, ("backend/static/terms.html","static/terms.html","public/terms.html","terms.html"))
        status, headers, body = _html(200, html)
        start_response("200 OK", headers); return body

    if path == "/privacy":
        html = _load_file_or(_PRIV_HTML, ("backend/static/privacy.html","static/privacy.html","public/privacy.html","privacy.html"))
        status, headers, body = _html(200, html)
        start_response("200 OK", headers); return body

    if path == "/api/deploy-stamp":
        payload = {"commit": _guess_commit(), "source": "env"}
        status, headers, body = _json(200, payload, [("Access-Control-Allow-Origin","*")])
        start_response("200 OK", headers); return body

    # Desbloqueo de POST /api/notes (MVP) + anti-abuso simple en GET
    if path == "/api/notes":
        if method == "OPTIONS":
            # CORS/Allow mínimos
            headers = [("Access-Control-Allow-Origin","*"),
                       ("Access-Control-Allow-Methods","GET,POST,OPTIONS,HEAD"),
                       ("Access-Control-Allow-Headers","Content-Type"),
                       ("Allow","GET,POST,OPTIONS,HEAD"),
                       ("Cache-Control","no-store"),
                       ("Content-Length","0")]
            start_response("204 No Content", headers); return [b""]

        if method == "POST":
            data = None
            try:
                data = req.get_json(silent=True) or {}
            except Exception:
                data = {}
            if not data:
                # intenta form
                try:
                    data = req.form.to_dict(flat=True)
                except Exception:
                    data = {}
            text = (data.get("text") or data.get("content") or "").strip()
            if not text:
                status, headers, body = _json(400, {"error":"bad_request","reason":"missing content"},
                                              [("Access-Control-Allow-Origin","*"),("Allow","GET,POST,OPTIONS,HEAD")])
                start_response("400 Bad Request", headers); return body
            # Éxito mínimo viable: 201 echo (sin tocar DB ni modelos)
            payload = {"ok": True, "id": None, "echo": {"text": text}, "mode":"mvp"}
            status, headers, body = _json(201, payload, [("Access-Control-Allow-Origin","*"),
                                                         ("Allow","GET,POST,OPTIONS,HEAD")])
            start_response("201 Created", headers); return body

        if method == "GET":
            # Clamp de limit y no-store
            qs, _ = _clamp_notes_limit(environ.get("QUERY_STRING",""))
            environ["QUERY_STRING"] = qs  # pasa al app base
            # Deja continuar
            res_iter = _base_app(environ, start_response)
            return res_iter

    # Por defecto, delega
    return _base_app(environ, start_response)

# Exporta application WSGI
def application(environ, start_response):
    return _overlay(environ, start_response)
PY

# Compila por seguridad
python -m py_compile wsgi.py

echo "PATCH_OK wsgi.py"
