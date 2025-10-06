# -*- coding: utf-8 -*-
import os, json

def _p12_guess_commit():
    """Best-effort commit discovery without regex."""
    hexdigits = set("0123456789abcdef")
    for key in ("RENDER_GIT_COMMIT", "GIT_COMMIT", "SOURCE_COMMIT", "COMMIT_SHA"):
        value = os.environ.get(key)
        if value:
            v = value.strip().lower()
            if 7 <= len(v) <= 40 and all(c in hexdigits for c in v):
                return v
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

def _insert_into_head_once(html, marker_substring, snippet):
    """Insert snippet before </head> if marker not present; avoids regex usage."""
    if marker_substring.lower() in html.lower():
        return html
    lc = html.lower()
    i = lc.find("</head>")
    if i != -1:
        return html[:i] + snippet + "\n" + html[i:]
    return snippet + html

def _ensure_flags(html):
    commit = _p12_guess_commit() or "unknown"
    # meta commit
    meta_commit = '  <meta name="p12-commit" content="' + commit + '">'
    html = _insert_into_head_once(html, 'name="p12-commit"', meta_commit)
    # p12-safe-shim
    shim = (
      "  <meta name=\"p12-safe-shim\" content=\"1\">\n"
      "  <script>\n"
      "  /*! p12-safe-shim */\n"
      "  (function(){\n"
      "    window.p12FetchJson = async function(url,opts){\n"
      "      const ac = new AbortController(); const t=setTimeout(()=>ac.abort(),8000);\n"
      "      try{\n"
      "        const r = await fetch(url, Object.assign({headers:{'Accept':'application/json'}},opts||{}, {signal:ac.signal}));\n"
      "        const ct = (r.headers.get('content-type')||'').toLowerCase();\n"
      "        const isJson = ct.includes('application/json');\n"
      "        return { ok:r.ok, status:r.status, json: isJson? await r.json().catch(()=>null) : null };\n"
      "      } finally { clearTimeout(t); }\n"
      "    };\n"
      "    try{\n"
      "      var u=new URL(location.href);\n"
      "      if(u.searchParams.get('id')){ (document.body||document.documentElement).setAttribute('data-single','1'); }\n"
      "    }catch(_){}\n"
      "  })();\n"
      "  </script>\n"
    )
    html = _insert_into_head_once(html, 'p12-safe-shim', shim)
    # ensure body has data-single="1"
    lhtml = html.lower()
    bpos = lhtml.find("<body")
    if bpos != -1:
        end = html.find('>', bpos)
        if end != -1:
            opening = html[bpos:end]
            if 'data-single=' not in opening.lower():
                opening = opening + ' data-single="1"'
                html = html[:bpos] + opening + html[end:]
            else:
                # normalize to value "1" if present with another value
                # very conservative: simple replace patterns
                for q in ('"', "'"):
                    token = 'data-single=' + q
                    tpos = opening.lower().find('data-single=')
                    if tpos != -1:
                        # replace any quoted value with 1
                        # find quote char
                        qpos = opening.find('"', tpos)
                        qalt = opening.find("'", tpos)
                        if qpos == -1 or (qalt != -1 and qalt < qpos):
                            qpos = qalt
                            q = "'"
                        else:
                            q = '"'
                        if qpos != -1:
                            endq = opening.find(q, qpos+1)
                            if endq != -1:
                                opening = opening[:qpos+1] + '1' + opening[endq:]
                                html = html[:bpos] + opening + html[end:]
                                break
    else:
        html = '<body data-single="1"></body>' + html
    return html

def _p12_index_override_mw(app):
    def _app(env, start_response):
        p = env.get("PATH_INFO","/")
        if p in ("/","/index.html"):
            body=_ensure_flags(_p12_load_index_text()).encode("utf-8")
            start_response("200 OK",[("Content-Type","text/html; charset=utf-8"),("Cache-Control","no-cache"),("Content-Length",str(len(body)))])
            return [body]
        if p=="/terms":
            txt=_load_file(("backend/static/terms.html","static/terms.html","public/terms.html")) or "<!doctype html><title>Términos</title><h1>Términos</h1><p>En preparación.</p>"
            body=txt.encode("utf-8")
            start_response("200 OK",[("Content-Type","text/html; charset=utf-8"),("Cache-Control","no-cache"),("Content-Length",str(len(body)))])
            return [body]
        if p=="/privacy":
            txt=_load_file(("backend/static/privacy.html","static/privacy.html","public/privacy.html")) or "<!doctype html><title>Privacidad</title><h1>Privacidad</h1><p>En preparación.</p>"
            body=txt.encode("utf-8")
            start_response("200 OK",[("Content-Type","text/html; charset=utf-8"),("Cache-Control","no-cache"),("Content-Length",str(len(body)))])
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

# Importa la app Flask y envuélvela (prefiere backend.create_app si está disponible)
try:
    from backend import create_app  # type: ignore
    _base_app = create_app()
except Exception:
    try:
        from wsgiapp import application as _base_app  # type: ignore
    except Exception:
        _base_app = (lambda e, sr: (sr("404 Not Found",[("Content-Length","0")]) or [b""]))

application = _p12_index_override_mw(_base_app)
