#!/usr/bin/env bash
set -euo pipefail
PY="wsgi.py"
[[ -f "$PY" ]] || { echo "ERROR: falta $PY"; exit 1; }

python - <<'PY'
import io, os, re, py_compile, json
p="wsgi.py"
s=io.open(p,"r",encoding="utf-8").read()

def upsert(mod):
    # imports mínimos
    head=[]
    if re.search(r'^\s*import\s+os\b', mod, re.M) is None: head.append('import os')
    if re.search(r'^\s*import\s+re\b', mod, re.M) is None: head.append('import re')
    if re.search(r'^\s*import\s+json\b', mod, re.M) is None: head.append('import json')
    if head: mod = "\n".join(head) + "\n" + mod

    # No dejar .format() aplicado a HTML/JS (causa ValueError por llaves)
    mod = re.sub(r'\)\.format\s*\([^)]*\)', ')  # p12: .format() removido', mod)

    # Inyectar MW sólo si falta
    if "_p12_index_override_mw" not in mod:
        mod += r'''
# --- paste12: WSGI middleware robusto (sin .format en HTML) ---
def _p12_guess_commit():
    for k in ("RENDER_GIT_COMMIT","GIT_COMMIT","SOURCE_COMMIT","COMMIT_SHA"):
        v=os.environ.get(k)
        if v and re.fullmatch(r"[0-9a-f]{7,40}", v): return v
    return None

def _load_file(cands):
    for f in cands:
        try:
            with open(f,"r",encoding="utf-8") as fh:
                return fh.read()
        except Exception:
            pass
    return None

def _p12_load_index_text():
    txt = _load_file((
        "backend/static/index.html",
        "static/index.html",
        "public/index.html",
        "index.html",
        "wsgiapp/templates/index.html",
    ))
    if txt: return txt
    return "<!doctype html><head></head><body>paste12</body>"

def _inject_once(html, needle_regex, insert_html, where="head"):
    if re.search(needle_regex, html, re.I):
        return html
    if where=="head" and "</head>" in html:
        return re.sub(r'</head>', insert_html + "\\n</head>", html, count=1, flags=re.I)
    if where=="body" and "<body" in html:
        return re.sub(r'<body([^>]*)>', r'<body\\1>' + insert_html, html, count=1, flags=re.I)
    return insert_html + html

def _ensure_flags(html):
    commit=_p12_guess_commit() or "unknown"
    # meta p12-commit
    html=_inject_once(html, r'name=["\\\']p12-commit["\\\']', 
        f'  <meta name="p12-commit" content="{commit}">', "head")
    # p12-safe-shim + data-single
    shim = """
  <meta name="p12-safe-shim" content="1">
  <script>
  /*! p12-safe-shim */
  (function(){
    window.p12FetchJson = async function(url,opts){
      const ac = new AbortController(); const t=setTimeout(()=>ac.abort(),8000);
      try{
        const r = await fetch(url, Object.assign({headers:{'Accept':'application/json'}},opts||{}, {signal:ac.signal}));
        const ct = (r.headers.get('content-type')||'').toLowerCase();
        const isJson = ct.includes('application/json');
        return { ok:r.ok, status:r.status, json: isJson? await r.json().catch(()=>null) : null };
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
    html=_inject_once(html, r'p12-safe-shim', shim, "head")
    # data-single="1"
    if re.search(r'<body[^>]*data-single=', html, re.I):
        html=re.sub(r'(<body[^>]*data-single=)["\\\'][^"\\\']*', r'\\1"1', html, flags=re.I)
    else:
        html=re.sub(r'<body', '<body data-single="1"', html, count=1, flags=re.I) if "<body" in html else ('<body data-single="1"></body>'+html)
    return html

def _p12_index_override_mw(app):
    def _app(env, start_response):
        p = env.get("PATH_INFO","/")
        if p in ("/","/index.html"):
            body=_ensure_flags(_p12_load_index_text()).encode("utf-8")
            start_response("200 OK",[("Content-Type","text/html; charset=utf-8"),("Cache-Control","no-store"),("Content-Length",str(len(body)))])
            return [body]
        if p=="/terms":
            txt=_load_file(("backend/static/terms.html","static/terms.html","public/terms.html")) or "<!doctype html><title>Términos</title><h1>Términos</h1><p>En preparación.</p>"
            body=txt.encode("utf-8")
            start_response("200 OK",[("Content-Type","text/html; charset=utf-8"),("Cache-Control","no-store"),("Content-Length",str(len(body)))])
            return [body]
        if p=="/privacy":
            txt=_load_file(("backend/static/privacy.html","static/privacy.html","public/privacy.html")) or "<!doctype html><title>Privacidad</title><h1>Privacidad</h1><p>En preparación.</p>"
            body=txt.encode("utf-8")
            start_response("200 OK",[("Content-Type","text/html; charset=utf-8"),("Cache-Control","no-store"),("Content-Length",str(len(body)))])
            return [body]
        if p=="/api/deploy-stamp":
            c=_p12_guess_commit()
            if not c:
                b=json.dumps({"error":"not_found"}).encode("utf-8")
                start_response("404 Not Found",[("Content-Type","application/json"),("Cache-Control","no-store"),("Content-Length",str(len(b)))])
                return [b]
            b=json.dumps({"commit":c,"source":"env"}).encode("utf-8")
            start_response("200 OK",[("Content-Type","application/json"),("Cache-Control","no-store"),("Content-Length",str(len(b)))])
            return [b]
        return app(env, start_response)
    return _app
'''
    # Envolver 'application'
    if re.search(r'^\s*application\s*=\s*', mod, re.M):
        mod = mod + "\napplication = _p12_index_override_mw(application)\n"
    else:
        mod = mod + "\napplication = _p12_index_override_mw(globals().get('application') or (lambda e,sr: sr('404 Not Found',[]) or [b''']))\n"

    return mod

s = upsert(s)
io.open(p,"w",encoding="utf-8").write(s)
py_compile.compile("wsgi.py", doraise=True)
print("PATCH_OK wsgi.py")
PY
