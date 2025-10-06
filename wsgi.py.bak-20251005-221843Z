# paste12: WSGI mínimo, sin regex, con index flags y /api/deploy-stamp
import os, json

def _p12_guess_commit():
    for k in ("RENDER_GIT_COMMIT","GIT_COMMIT","SOURCE_COMMIT","COMMIT_SHA"):
        v=os.environ.get(k)
        if v and all(c in "0123456789abcdef" for c in v.lower()) and 7<=len(v)<=40:
            return v
    return None

def _p12_load_index_text():
    cands=("backend/static/index.html","static/index.html","public/index.html",
           "index.html","wsgiapp/templates/index.html")
    for f in cands:
        try:
            with open(f,"r",encoding="utf-8") as fh:
                return fh.read()
        except Exception:
            continue
    # fallback mínimo si no hay archivo
    c=_p12_guess_commit() or "unknown"
    return "<!doctype html><head><meta name='p12-commit' content='%s'><meta name='p12-safe-shim' content='1'></head><body data-single='1'>paste12</body>"%c

def _p12_ensure_flags(html:str)->str:
    c=_p12_guess_commit() or "unknown"
    # meta p12-commit (insertar o actualizar)
    if "name=\"p12-commit\"" in html or "name='p12-commit'" in html:
        # reemplazo naïf del content= (sin regex)
        for q in ('"', "'"):
            needle=f'name={q}p12-commit{q}'
            if needle in html:
                # buscar content="..."
                i=html.find(needle)
                if i!=-1:
                    j=html.find("content=", i)
                    if j!=-1:
                        k1=html.find('"', j)
                        k2=html.find("'", j)
                        if k1==-1 or (k2!=-1 and k2<k1):  # usa comilla simple
                            q2="'"
                            a=html.find(q2, j); b=html.find(q2, a+1) if a!=-1 else -1
                            if a!=-1 and b!=-1:
                                html=html[:a+1]+c+html[b:]
                        else:  # usa comilla doble
                            q2='"'
                            a=html.find(q2, j); b=html.find(q2, a+1) if a!=-1 else -1
                            if a!=-1 and b!=-1:
                                html=html[:a+1]+c+html[b:]
                break
    else:
        # insertar dentro de </head> si existe, o al comienzo
        tag='</head>'
        meta=f'<meta name="p12-commit" content="{c}">'
        if tag in html:
            html=html.replace(tag, meta+"\n"+tag, 1)
        else:
            html=f"<head>{meta}</head>"+html

    # meta p12-safe-shim
    if ("p12-safe-shim" not in html):
        shim = (
          '<meta name="p12-safe-shim" content="1">\n'
          '<script>\n'
          '/*! p12-safe-shim */\n'
          '(function(){\n'
          '  window.p12FetchJson = async function(url,opts){\n'
          '    const ac=new AbortController(); const t=setTimeout(()=>ac.abort(),8000);\n'
          '    try{ const r=await fetch(url,Object.assign({headers:{\"Accept\":\"application/json\"}},opts||{},{signal:ac.signal}));\n'
          '      const ct=(r.headers.get(\"content-type\")||\"\").toLowerCase();\n'
          '      const isJson=ct.includes(\"application/json\");\n'
          '      return { ok:r.ok, status:r.status, json:isJson?await r.json().catch(()=>null):null };\n'
          '    } finally{ clearTimeout(t); }\n'
          '  };\n'
          '  try{ var u=new URL(location.href); if(u.searchParams.get(\"id\")){\n'
          '    (document.body||document.documentElement).setAttribute(\"data-single\",\"1\"); }\n'
          '  }catch(_){}\n'
          '})();\n'
          '</script>\n'
        )
        tag='</head>'
        if tag in html: html=html.replace(tag, shim+tag, 1)
        else: html=f"<head>{shim}</head>"+html

    # body data-single
    low=html.lower()
    i=low.find("<body")
    if i!=-1:
        j=low.find(">", i)
        if "data-single" not in low[i:j]:
            html = html[:j] + ' data-single="1"' + html[j:]
    else:
        html += '<body data-single="1"></body>'
    return html

# cargar aplicación base
try:
    from wsgiapp import application as _base_app
except Exception as _e:
    def _base_app(env, sr):
        body=b'{"error":"app_import_failed"}'
        sr("500 Internal Server Error",[("Content-Type","application/json"),("Content-Length",str(len(body)))])
        return [body]

def _mw(app):
    def _app(env, start_response):
        path = env.get("PATH_INFO","/")
        if path in ("/","/index.html"):
            body = _p12_ensure_flags(_p12_load_index_text()).encode("utf-8")
            headers=[("Content-Type","text/html; charset=utf-8"),("Cache-Control","no-store"),("Content-Length", str(len(body)))]
            start_response("200 OK", headers)
            return [body]
        if path == "/api/deploy-stamp":
            c=_p12_guess_commit()
            if not c:
                body=b'{"error":"not_found"}'
                start_response("404 Not Found",[("Content-Type","application/json"),("Cache-Control","no-cache"),("Content-Length",str(len(body)))])
                return [body]
            body=json.dumps({"commit":c,"source":"env"}).encode("utf-8")
            start_response("200 OK",[("Content-Type","application/json"),("Cache-Control","no-cache"),("Content-Length",str(len(body)))])
            return [body]
        return app(env, start_response)
    return _app

application = _mw(_base_app)
