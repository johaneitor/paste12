import os, json
# p12: minimal WSGI bootstrap with safe index and /api/deploy-stamp; no regex; conservative headers
try:
    from wsgiapp import application as _base_app  # underlying Flask app
except Exception:
    def _base_app(environ, start_response):
        start_response("404 Not Found", [("Content-Type","text/plain; charset=utf-8"),("Content-Length","9")])
        return [b"not found"]

def _commit():
    for k in ("RENDER_GIT_COMMIT","GIT_COMMIT","SOURCE_COMMIT","COMMIT_SHA"):
        v=os.environ.get(k)
        if v and all(c in "0123456789abcdef" for c in v.lower()):
            return v
    return None

def _load_index():
    for f in ("backend/static/index.html","static/index.html","public/index.html","index.html"):
        try:
            with open(f,"rb") as fh:
                return fh.read()
        except Exception:
            pass
    c = _commit() or "unknown"
    body = ("<!doctype html><head>"
            '<meta name="p12-commit" content="%s">'
            '<meta name="p12-safe-shim" content="1"></head>'
            '<body data-single="1">paste12</body>' % c)
    return body.encode("utf-8")

def _ensure_flags(html_bytes):
    s = html_bytes.decode("utf-8", "replace")
    if "p12-commit" not in s:
        s = s.replace("</head>", '<meta name="p12-commit" content="%s"></head>' % (_commit() or "unknown"))
    if "p12-safe-shim" not in s:
        s = s.replace("</head>", '<meta name="p12-safe-shim" content="1"></head>')
    if "data-single" not in s:
        s = s.replace("<body", '<body data-single="1"', 1)
    return s.encode("utf-8")

def _wrap(app):
    def _app(environ, start_response):
        path = environ.get("PATH_INFO","/")
        if path in ("/", "/index.html"):
            b = _ensure_flags(_load_index())
            start_response("200 OK", [("Content-Type","text/html; charset=utf-8"),
                                      ("Cache-Control","no-store"),
                                      ("Content-Length",str(len(b)))])
            return [b]
        if path == "/api/deploy-stamp":
            c = _commit()
            if not c:
                b = json.dumps({"error":"not_found"}).encode("utf-8")
                start_response("404 Not Found", [("Content-Type","application/json"),
                                                 ("Cache-Control","no-store"),
                                                 ("Content-Length",str(len(b)))])
                return [b]
            b = json.dumps({"commit":c,"source":"env"}).encode("utf-8")
            start_response("200 OK", [("Content-Type","application/json"),
                                      ("Cache-Control","no-store"),
                                      ("Content-Length",str(len(b)))])
            return [b]
        if path in ("/terms","/privacy"):
            try:
                content = open("backend/static%s.html" % path, "rb").read()
            except Exception:
                title = path.strip("/")
                content = ("<!doctype html><title>%s</title>%s" % (title, title)).encode("utf-8")
            start_response("200 OK", [("Content-Type","text/html; charset=utf-8"),
                                      ("Cache-Control","no-store"),
                                      ("Content-Length",str(len(content)))])
            return [content]
        return app(environ, start_response)
    return _app

application = _wrap(_base_app)
