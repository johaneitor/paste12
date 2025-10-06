#!/usr/bin/env bash
set -euo pipefail
PY="wsgi.py"
[[ -f "$PY" ]] || { echo "ERROR: no existe $PY"; exit 1; }

cp -f "$PY" "${PY}.bak-$(date -u +%Y%m%d-%H%M%SZ)"

python - "$PY" <<'PYCODE'
import io, os, re, json, py_compile, sys
p = sys.argv[1]
s = io.open(p, "r", encoding="utf-8").read()

def ensure_imports(t):
    if not re.search(r'^\s*import\s+os\b', t, re.M):   t = "import os\n"   + t
    if not re.search(r'^\s*import\s+re\b', t, re.M):   t = "import re\n"   + t
    if not re.search(r'^\s*import\s+json\b', t, re.M): t = "import json\n" + t
    return t

s = ensure_imports(s)

patch = r"""
# === paste12: root/index middleware (sin regex en HTML) ===
def _p12_guess_commit():
    for k in ("RENDER_GIT_COMMIT","GIT_COMMIT","SOURCE_COMMIT","COMMIT_SHA"):
        v = os.environ.get(k)
        if v and re.fullmatch(r"[0-9a-f]{7,40}", v):
            return v
    return "unknown"

def _p12_read_first(*paths):
    for f in paths:
        try:
            with open(f, "r", encoding="utf-8") as fh:
                return fh.read()
        except Exception:
            continue
    return None

def _p12_min_index():
    c = _p12_guess_commit()
    return (
        "<!doctype html>"
        "<head><meta charset='utf-8'>"
        "<meta name='p12-commit' content='"+c+"'>"
        "<meta name='p12-safe-shim' content='1'></head>"
        "<body data-single='1'>paste12</body>"
    )

def _p12_ensure_flags(html):
    h = html or _p12_min_index()
    c = _p12_guess_commit()
    lo = h.lower()
    # p12-commit
    if "p12-commit" not in lo:
        pos = lo.find("</head>")
        tag = f"<meta name='p12-commit' content='{c}'>"
        h = h[:pos] + tag + h[pos:] if pos != -1 else f"<head>{tag}</head>"+h
    # p12-safe-shim
    if "p12-safe-shim" not in lo:
        pos = h.lower().find("</head>")
        tag = "<meta name='p12-safe-shim' content='1'>"
        h = h[:pos] + tag + h[pos:] if pos != -1 else f"<head>{tag}</head>"+h
    # data-single
    if "data-single" not in lo:
        h = h.replace("<body", "<body data-single='1'", 1)
    return h

def _p12_index_bytes():
    html = _p12_read_first(
        "backend/static/index.html","static/index.html","public/index.html",
        "index.html","wsgiapp/templates/index.html"
    )
    html = _p12_ensure_flags(html)
    b = html.encode("utf-8")
    return b, [("Content-Type","text/html; charset=utf-8"),
               ("Cache-Control","no-cache"),
               ("Content-Length", str(len(b)))]

def _p12_json(d, status="200 OK"):
    b = json.dumps(d).encode("utf-8")
    return b, status, [("Content-Type","application/json"),
                       ("Cache-Control","no-cache"),
                       ("Content-Length", str(len(b)))]

def _p12_root_mw(app):
    def _app(env, start_response):
        path = env.get("PATH_INFO","/")
        if path in ("/", "/index.html"):
            body, headers = _p12_index_bytes()
            start_response("200 OK", headers)
            return [body]
        if path == "/api/deploy-stamp":
            c = _p12_guess_commit()
            if c == "unknown":
                body, status, headers = _p12_json({"error":"not_found"}, "404 Not Found")
            else:
                body, status, headers = _p12_json({"commit":c,"source":"env"}, "200 OK")
            start_response(status, headers)
            return [body]
        if path in ("/terms","/privacy"):
            name = path.strip("/")
            html = _p12_read_first(f"backend/static/{name}.html",
                                   f"static/{name}.html",
                                   f"public/{name}.html")
            if html:
                b = html.encode("utf-8")
                start_response("200 OK", [("Content-Type","text/html; charset=utf-8"),
                                          ("Cache-Control","no-cache"),
                                          ("Content-Length", str(len(b)))])
                return [b]
        return app(env, start_response)
    return _app

# Envolver 'application' existente o crear dummy si falta
try:
    application = _p12_root_mw(application)  # type: ignore[name-defined]
except NameError:
    def _dummy_app(e, sr):
        sr("404 Not Found", [("Content-Type","text/plain"),("Content-Length","0")])
        return [b""]
    application = _p12_root_mw(_dummy_app)
# === fin paste12 MW ===
"""

if "_p12_root_mw" not in s:
    s = s + "\n" + patch + "\n"

io.open(p, "w", encoding="utf-8").write(s)
py_compile.compile(p, doraise=True)
print("PATCH_OK", p)
PYCODE

python -m py_compile wsgi.py
python -m py_compile wsgiapp/__init__.py
echo "OK: wsgi.py y wsgiapp/__init__.py compilados"
