#!/usr/bin/env bash
set -euo pipefail
PY="wsgi.py"
cp -f "$PY" "${PY}.bak-$(date -u +%Y%m%d-%H%M%SZ)" 2>/dev/null || true

cat > "$PY" <<'PYFILE'
# -*- coding: utf-8 -*-
import os, json

def _p12_guess_commit():
    for k in ("RENDER_GIT_COMMIT","GIT_COMMIT","SOURCE_COMMIT","COMMIT_SHA"):
        v=os.environ.get(k)
        if v and all(c in "0123456789abcdef" for c in v.lower()) and 7<=len(v)<=40:
            return v
    return None

def _p12_load_index_text():
    cands=("backend/static/index.html","static/index.html","public/index.html","index.html","wsgiapp/templates/index.html")
    for f in cands:
        try:
            with open(f,"r",encoding="utf-8") as fh:
                return fh.read()
        except Exception:
            pass
    c=_p12_guess_commit() or "unknown"
    return "<!doctype html><head><meta name='p12-commit' content='%s'></head><body data-single='1'>paste12</body>"%c

def _insert_before_lower(html, tag_lower, snippet):
    low = html.lower()
    i = low.find(tag_lower)
    if i >= 0:
        return html[:i] + snippet + html[i:]
    return "<head>"+snippet+"</head>"+html

def _ensure_meta_commit(html):
    c=_p12_guess_commit() or "unknown"
    low=html.lower()
    if 'name="p12-commit"' in low or "name='p12-commit'" in low:
        # ya hay meta; no lo tocamos
        return html
    snippet = '  <meta name="p12-commit" content="'+c+'">\\n'
    return _insert_before_lower(html, "</head>", snippet)

def _ensure_safe_shim(html):
    low=html.lower()
    if "p12-safe-shim" in low:
        return html
    shim = """  <meta name="p12-safe-shim" content="1">
  <script>
  /*! p12-safe-shim */
  (function(){
    window.p12FetchJson = async function(url,opts){
      const ac = new AbortController(); const t=setTimeout(()=>ac.abort(),8000);
      try{
        const r = await fetch(url, Object.assign({headers:{'Accept':'application/json'}},opts||{}, {signal:ac.signal}));
        const ct = (r.headers.get('content-type')||'').toLowerCase();
        const ok = r.ok, st=r.status; let js=null;
        if (ct.includes('application/json')) { try{ js=await r.json(); }catch(_){ js=null; } }
        return { ok:ok, status:st, json:js };
      } finally { clearTimeout(t); }
    };
    try{
      var u=new URL(location.href);
      if(u.searchParams.get('id')){
        (document.body||document.documentElement).setAttribute('data-single','1');
      }
    }catch(_){}
  })();
  </script>
"""
    return _insert_before_lower(html, "</head>", shim)

def _ensure_body_single(html):
    low=html.lower()
    i = low.find("<body")
    if i < 0:
        return html + "<body data-single='1'></body>"
    if "data-single" in low[i: low.find(">", i)+1]:
        return html
    # insertar atributo antes del '>' del body
    j = html.find(">", i)
    if j < 0:
        return html
    return html[:i+5] + ' data-single="1"' + html[i+5:]

def _ensure_flags(html):
    html = _ensure_meta_commit(html)
    html = _ensure_safe_shim(html)
    html = _ensure_body_single(html)
    return html

def _index_override(app):
    def _app(environ, start_response):
        path = environ.get("PATH_INFO","/")
        if path in ("/","/index.html"):
            body = _ensure_flags(_p12_load_index_text()).encode("utf-8")
            headers=[("Content-Type","text/html; charset=utf-8"),
                     ("Cache-Control","no-store"),
                     ("Content-Length", str(len(body)))]
            start_response("200 OK", headers)
            return [body]
        if path == "/api/deploy-stamp":
            c=_p12_guess_commit()
            if not c:
                body=json.dumps({"error":"not_found"}).encode("utf-8")
                start_response("404 Not Found",[("Content-Type","application/json"),("Content-Length",str(len(body)))])
                return [body]
            body=json.dumps({"commit":c,"source":"env"}).encode("utf-8")
            start_response("200 OK",[("Content-Type","application/json"),("Cache-Control","no-cache"),("Content-Length",str(len(body)))])
            return [body]
        return app(environ, start_response)
    return _app

# Base app: preferimos wsgiapp.application > wsgiapp.app; fallback mínimo ok
def _fallback_app(environ, start_response):
    start_response("200 OK",[("Content-Type","text/plain")])
    return [b"ok"]

base_app = _fallback_app
try:
    from wsgiapp import application as base_app  # noqa
except Exception:
    try:
        from wsgiapp import app as base_app  # noqa
    except Exception:
        base_app = _fallback_app

# Export final
application = _index_override(base_app)
PYFILE

python -m py_compile "$PY"
echo "PATCH_OK $PY"
