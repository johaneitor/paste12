from urllib.parse import parse_qs
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

# --- p12: API override (POST/OPTIONS /api/notes + REST 404 guard) ---
def _p12_read_body(environ):
    try: ln = int(environ.get('CONTENT_LENGTH') or '0')
    except Exception: ln = 0
    if ln>0 and environ.get('wsgi.input'): return environ['wsgi.input'].read(ln)
    return b''

def _p12_api_override_mw(app):
    def _app(environ, start_response):
        path   = environ.get('PATH_INFO','/')
        method = (environ.get('REQUEST_METHOD') or 'GET').upper()

        # CORS preflight
        if path == '/api/notes' and method == 'OPTIONS':
            headers=[('Access-Control-Allow-Origin','*'),
                     ('Access-Control-Allow-Methods','GET, POST, OPTIONS'),
                     ('Access-Control-Allow-Headers','Content-Type'),
                     ('Cache-Control','no-store'),
                     ('Content-Length','0')]
            start_response('204 No Content', headers); return [b'']

        # POST /api/notes
        if path == '/api/notes' and method == 'POST':
            ctype = (environ.get('CONTENT_TYPE') or '').lower()
            raw   = _p12_read_body(environ)
            text  = None
            if 'application/json' in ctype:
                try:
                    j=json.loads(raw.decode('utf-8') or '{}')
                    if isinstance(j,dict): text=j.get('text')
                except Exception: text=None
            elif 'application/x-www-form-urlencoded' in ctype:
                try:
                    q=parse_qs(raw.decode('utf-8'), keep_blank_values=True)
                    vs=q.get('text') or []; text=vs[0] if vs else None
                except Exception: text=None
            if not text:
                data=b'{"error":"bad_request","hint":"text required"}'
                headers=[('Content-Type','application/json'),
                         ('Access-Control-Allow-Origin','*'),
                         ('Cache-Control','no-store'),
                         ('Content-Length',str(len(data)))]
                start_response('400 Bad Request', headers); return [data]

            nid=None
            try:
                # Usa el app real para DB/Model
                from wsgiapp import db, Note
                fl = app
                if hasattr(fl,'app_context'):
                    with fl.app_context():
                        obj=Note(text=text); db.session.add(obj); db.session.commit()
                        nid=getattr(obj,'id',None)
            except Exception:
                nid=None

            try: nid_json=int(nid) if isinstance(nid,(int,)) or (isinstance(nid,str) and nid.isdigit()) else nid
            except Exception: nid_json=nid
            payload=json.dumps({'id':nid_json,'created':bool(nid)}).encode('utf-8')
            headers=[('Content-Type','application/json'),
                     ('Access-Control-Allow-Origin','*'),
                     ('Cache-Control','no-store'),
                     ('Content-Length',str(len(payload)))]
            start_response('201 Created' if nid is not None else '202 Accepted', headers)
            return [payload]

        # REST 404 guard para inexistentes
        m=re.match(r'^/api/notes/(\d+)/(like|view|report)$', path)
        if m and method in ('GET','POST'):
            exists=False
            try:
                from wsgiapp import db, Note
                fl = app
                if hasattr(fl,'app_context'):
                    with fl.app_context():
                        row=db.session.get(Note, int(m.group(1)))
                        exists = (row is not None)
            except Exception:
                exists=False
            if not exists:
                data=b'{"error":"not_found"}'
                headers=[('Content-Type','application/json'),
                         ('Access-Control-Allow-Origin','*'),
                         ('Cache-Control','no-store'),
                         ('Content-Length',str(len(data)))]
                start_response('404 Not Found', headers); return [data]

        return app(environ, start_response)
    return _app

application = _p12_api_override_mw(application)
