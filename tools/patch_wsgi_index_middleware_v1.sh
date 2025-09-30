#!/usr/bin/env bash
set -euo pipefail

PYFILE="wsgi.py"
[[ -f "$PYFILE" ]] || { echo "ERROR: no existe $PYFILE (entrada de gunicorn)."; exit 1; }

python - <<'PY'
import io,os,re,py_compile,shutil,time
p="wsgi.py"
s=io.open(p,"r",encoding="utf-8").read()

if "_p12_index_override_mw" not in s:
    # asegurar imports
    if re.search(r'^\s*import\s+os\b', s, re.M) is None: s="import os\n"+s
    if re.search(r'^\s*import\s+re\b', s, re.M) is None: s="import re\n"+s

    s += r"""

# --- paste12: middleware para index y deploy-stamp (WSGI) ---
def _p12_guess_commit():
    for k in ("RENDER_GIT_COMMIT","GIT_COMMIT","SOURCE_COMMIT","COMMIT_SHA"):
        v=os.environ.get(k)
        if v and re.fullmatch(r"[0-9a-f]{7,40}", v): return v
    return None

def _p12_load_index_text():
    cands=("backend/static/index.html","static/index.html","public/index.html","index.html","wsgiapp/templates/index.html")
    for f in cands:
        try:
            with open(f,"r",encoding="utf-8") as fh:
                return fh.read()
        except Exception:
            continue
    # mínimo de cortesía si no hay archivo
    return "<!doctype html><meta name='p12-commit' content='{}'><body data-single='1'>paste12</body>".format(_p12_guess_commit() or "unknown")

def _p12_ensure_flags(html):
    # inyectar meta p12-commit, p12-safe-shim y data-single="1"
    commit=_p12_guess_commit() or "unknown"
    # p12-commit
    if re.search(r'name=["\']p12-commit["\']', html, re.I):
        html=re.sub(r'(name=["\']p12-commit["\']\s+content=["\'])[0-9a-f]{7,40}(["\'])', r'\1'+commit+r'\2', html, flags=re.I)
    else:
        html=re.sub(r'</head>', '  <meta name="p12-commit" content="'+commit+'">\\n</head>', html, count=1, flags=re.I) if "</head>" in html else ('<head><meta name="p12-commit" content="'+commit+'"></head>'+html)

    # p12-safe-shim marker + inline shim si falta
    if re.search(r'p12-safe-shim', html, re.I) is None:
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
        html = re.sub(r'</head>', shim+'\n</head>', html, count=1, flags=re.I) if "</head>" in html else ('<head>'+shim+'</head>'+html)

    # data-single="1" en <body>
    if re.search(r'<body[^>]*data-single=', html, re.I):
        html=re.sub(r'(<body[^>]*data-single=)["\'][^"\']*', r'\1"1', html, flags=re.I)
    else:
        html=re.sub(r'<body', '<body data-single="1"', html, count=1, flags=re.I) if "<body" in html else (html+'<body data-single="1"></body>')

    return html

def _p12_index_override_mw(app):
    def _app(env, start_response):
        path = env.get("PATH_INFO","/")
        if path in ("/", "/index.html"):
            body = _p12_ensure_flags(_p12_load_index_text())
            body_b = body.encode("utf-8")
            headers=[("Content-Type","text/html; charset=utf-8"),
                     ("Cache-Control","no-cache"),
                     ("Content-Length", str(len(body_b)))]
            start_response("200 OK", headers)
            return [body_b]
        if path == "/api/deploy-stamp":
            import json
            c=_p12_guess_commit()
            if not c:
                body=json.dumps({"error":"not_found"}).encode("utf-8")
                start_response("404 Not Found",[("Content-Type","application/json"),("Content-Length",str(len(body)))])
                return [body]
            body=json.dumps({"commit":c,"source":"env"}).encode("utf-8")
            start_response("200 OK",[("Content-Type","application/json"),("Cache-Control","no-cache"),("Content-Length",str(len(body)))])
            return [body]
        return app(env, start_response)
    return _app
"""
    # envolver 'application' si existe
    if re.search(r'^\s*application\s*=\s*', s, re.M):
        s = s + "\napplication = _p12_index_override_mw(application)\n"
    else:
        # si no hay símbolo application, exportar uno mínimo
        s = s + "\n\n# exportar application si faltara\napplication = _p12_index_override_mw(globals().get('application') or (lambda e,sr: sr('404 Not Found',[]) or [b'']))\n"

    io.open(p,"w",encoding="utf-8").write(s)

py_compile.compile(p, doraise=True)
print("PATCH_OK", p)
PY

git add wsgi.py
git commit -m "WSGI: override '/' with ensured index (p12-commit/safe-shim/single) + /api/deploy-stamp [p12]" || true
