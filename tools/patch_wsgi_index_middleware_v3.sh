#!/usr/bin/env bash
set -euo pipefail
PYFILE="wsgi.py"
[[ -f "$PYFILE" ]] || { echo "ERROR: no existe $PYFILE (entrada de gunicorn)."; exit 1; }
python - <<'PY'
import io, os, re, py_compile, textwrap

p = "wsgi.py"
s = io.open(p, "r", encoding="utf-8").read()

def ensure_imports(src:str)->str:
    for imp in ("os","re"):
        if re.search(rf'^\s*import\s+{imp}\b', src, re.M) is None:
            src = f"import {imp}\n"+src
    if re.search(r'^\s*from\s+textwrap\s+import\s+dedent\b', src, re.M) is None:
        src = "from textwrap import dedent\n"+src
    return src

def patch(src:str)->str:
    if "_p12_index_override_mw" in src and "_p12_serve_static_file" in src:
        return src  # ya parcheado v3
    src = ensure_imports(src)
    src += "\n" + textwrap.dedent(r'''
        # --- paste12: middleware index + deploy-stamp + fallbacks estáticos ---
        def _p12_guess_commit():
            for k in ('RENDER_GIT_COMMIT','RENDER_GIT_COMMIT_SHA','GIT_COMMIT','SOURCE_COMMIT','COMMIT_SHA'):
                v = os.environ.get(k)
                if v and re.fullmatch(r'[0-9a-f]{7,40}', v): return v
            return None

        def _p12_load_text(candidates):
            for f in candidates:
                try:
                    with open(f,'r',encoding='utf-8') as fh:
                        return fh.read()
                except Exception:
                    pass
            return None

        def _p12_load_index_text():
            return _p12_load_text((
                'backend/static/index.html','static/index.html','public/index.html','index.html','wsgiapp/templates/index.html'
            )) or '<!doctype html><meta name="p12-commit" content="{}"><body data-single="1">paste12</body>'.format(_p12_guess_commit() or 'unknown')

        def _p12_ensure_flags(html):
            commit = _p12_guess_commit() or 'unknown'
            # p12-commit
            if re.search(r'name=["\']p12-commit["\']', html, re.I):
                html = re.sub(r'(name=["\']p12-commit["\']\s+content=["\'])[0-9a-f]{7,40}(["\'])', r'\1'+commit+r'\2', html, flags=re.I)
            else:
                html = html.replace('</head>', '  <meta name="p12-commit" content="'+commit+'">\\n</head>', 1) if '</head>' in html else ('<head><meta name="p12-commit" content="'+commit+'"></head>'+html)
            # safe-shim
            if re.search(r'p12-safe-shim', html, re.I) is None:
                shim = dedent('''\
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
                ''')
                html = html.replace('</head>', shim+'\\n</head>', 1) if '</head>' in html else ('<head>'+shim+'</head>'+html)
            # data-single
            if re.search(r'<body[^>]*data-single=', html, re.I):
                html = re.sub(r'(<body[^>]*data-single=)["\'][^"\']*', r'\1"1', html, flags=re.I)
            else:
                html = html.replace('<body', '<body data-single="1"', 1) if '<body' in html else (html+'<body data-single="1"></body>')
            return html

        def _p12_bytes(b):
            return b if isinstance(b,(bytes,bytearray)) else str(b).encode('utf-8')

        def _p12_serve_text(start_response, text, ctype):
            body = _p12_bytes(text)
            start_response('200 OK',[('Content-Type', ctype),('Cache-Control','no-cache'),('Content-Length',str(len(body)))])
            return [body]

        def _p12_serve_static_file(start_response, names, ctype='text/html; charset=utf-8', ensure_flags=False):
            txt = _p12_load_text(names)
            if txt is None:
                # fallback mínimo si falta el archivo
                txt = '<!doctype html><title>paste12</title><meta name="p12-commit" content="{}"><body data-single="1">static</body>'.format(_p12_guess_commit() or 'unknown')
                ensure_flags = True
            if ensure_flags and ctype.startswith('text/html'):
                txt = _p12_ensure_flags(txt)
            return _p12_serve_text(start_response, txt, ctype)

        def _p12_index_override_mw(app):
            def _app(env, start_response):
                path = env.get('PATH_INFO','/')
                if path in ('/','/index.html'):
                    return _p12_serve_static_file(start_response,
                        ('backend/static/index.html','static/index.html','public/index.html','index.html','wsgiapp/templates/index.html'),
                        'text/html; charset=utf-8', True)
                if path == '/terms':
                    return _p12_serve_static_file(start_response,
                        ('backend/static/terms.html','static/terms.html','public/terms.html','terms.html'), 'text/html; charset=utf-8', False)
                if path == '/privacy':
                    return _p12_serve_static_file(start_response,
                        ('backend/static/privacy.html','static/privacy.html','public/privacy.html','privacy.html'), 'text/html; charset=utf-8', False)
                if path == '/api/deploy-stamp':
                    import json
                    c=_p12_guess_commit()
                    if not c:
                        b=json.dumps({'error':'not_found'}).encode('utf-8')
                        start_response('404 Not Found',[('Content-Type','application/json'),('Content-Length',str(len(b)))])
                        return [b]
                    b=json.dumps({'commit':c,'source':'env'}).encode('utf-8')
                    start_response('200 OK',[('Content-Type','application/json'),('Cache-Control','no-cache'),('Content-Length',str(len(b)))])
                    return [b]
                return app(env, start_response)
            return _app
    ''')
    if re.search(r'^\s*application\s*=', s, re.M):
        s += "\napplication = _p12_index_override_mw(application)\n"
    else:
        s += '\napplication = _p12_index_override_mw(globals().get("application") or (lambda e,sr: sr("404 Not Found",[]) or [b""]))\n'
    return src

ns = patch(s)
io.open(p, "w", encoding="utf-8").write(ns)
py_compile.compile(p, doraise=True)
print("PATCH_OK", p)
PY
