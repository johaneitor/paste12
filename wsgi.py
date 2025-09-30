from textwrap import dedent
import re
import os
from backend import create_app  # type: ignore
application = create_app()

# --- paste12: middleware index + deploy-stamp ---
def _p12_guess_commit():
    for k in ('RENDER_GIT_COMMIT','RENDER_GIT_COMMIT_SHA','GIT_COMMIT','SOURCE_COMMIT','COMMIT_SHA'):
        v = os.environ.get(k)
        if v and re.fullmatch(r'[0-9a-f]{7,40}', v): return v
    return None

def _p12_load_index_text():
    for f in ('backend/static/index.html','static/index.html','public/index.html','index.html','wsgiapp/templates/index.html'):
        try:
            with open(f,'r',encoding='utf-8') as fh: return fh.read()
        except Exception:
            pass
    return '<!doctype html><meta name="p12-commit" content="{}"><body data-single="1">paste12</body>'.format(_p12_guess_commit() or 'unknown')

def _p12_ensure_flags(html):
    commit = _p12_guess_commit() or 'unknown'
    # p12-commit
    if re.search(r'name=["\']p12-commit["\']', html, re.I):
        html = re.sub(r'(name=["\']p12-commit["\']\s+content=["\'])[0-9a-f]{7,40}(["\'])', r'\1'+commit+r'\2', html, flags=re.I)
    else:
        html = html.replace('</head>', '  <meta name="p12-commit" content="'+commit+'">\n</head>', 1) if '</head>' in html else ('<head><meta name="p12-commit" content="'+commit+'"></head>'+html)
    # safe-shim
    if re.search(r'p12-safe-shim', html, re.I) is None:
        shim = dedent('''                  <meta name="p12-safe-shim" content="1">
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
        html = html.replace('</head>', shim+'\n</head>', 1) if '</head>' in html else ('<head>'+shim+'</head>'+html)
    # data-single
    if re.search(r'<body[^>]*data-single=', html, re.I):
        html = re.sub(r'(<body[^>]*data-single=)["\'][^"\']*', r'\1"1', html, flags=re.I)
    else:
        html = html.replace('<body', '<body data-single="1"', 1) if '<body' in html else (html+'<body data-single="1"></body>')
    return html

def _p12_index_override_mw(app):
    def _app(env, start_response):
        path = env.get('PATH_INFO','/')
        if path in ('/','/index.html'):
            body = _p12_ensure_flags(_p12_load_index_text()).encode('utf-8')
            start_response('200 OK', [('Content-Type','text/html; charset=utf-8'),('Cache-Control','no-cache'),('Content-Length',str(len(body)))])
            return [body]
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

application = _p12_index_override_mw(application)
