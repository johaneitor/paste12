import pathlib, re

P = pathlib.Path("wsgiapp/__init__.py")
s = P.read_text(encoding="utf-8")

changed = False

# 0) asegurar 'import os' en el tope
if not re.search(r'^\s*import\s+os\b', s, flags=re.M):
    s = re.sub(r'^(import[^\n]*\n)', r'\1import os\n', s, count=1, flags=re.M)
    changed = True

# 1) agregar wrapper si no existe
if "class _RootBridgeAndDiag" not in s:
    s += r"""

# === OUTERMOST WRAPPER: fuerza '/' desde el bridge + diagnóstico en /api/bridge-state ===
class _RootBridgeAndDiag:
    def __init__(self, inner):
        self.inner = inner

    def __call__(self, environ, start_response):
        path   = (environ.get("PATH_INFO","") or "")
        method = (environ.get("REQUEST_METHOD","GET") or "GET").upper()

        # --- diagnóstico ligero ---
        if path == "/api/bridge-state":
            import os, json, hashlib
            # detectar index que ve el bridge
            override = os.environ.get("WSGI_BRIDGE_INDEX") or ""
            try:
                _REPO_DIR = __import__("os").path.dirname(__import__("os").path.dirname(__file__))
            except Exception:
                _REPO_DIR = ""
            cands = [override] if override else [
                __import__("os").path.join(_REPO_DIR, "backend", "static", "index.html"),
                __import__("os").path.join(_REPO_DIR, "public",  "index.html"),
                __import__("os").path.join(_REPO_DIR, "frontend","index.html"),
                __import__("os").path.join(_REPO_DIR, "index.html"),
            ]
            resolved = None; size = None; sha256 = None; pastel = False
            try:
                for pth in cands:
                    if pth and __import__("os").path.isfile(pth):
                        resolved = pth
                        with open(pth, "rb") as f:
                            data = f.read()
                        size = len(data)
                        sha256 = hashlib.sha256(data).hexdigest()
                        pastel = (b'--teal:#8fd3d0' in data)
                        break
            except Exception:
                pass
            data = {
                "ok": True,
                "force_env": os.getenv("FORCE_BRIDGE_INDEX",""),
                "force_bool": (os.getenv("FORCE_BRIDGE_INDEX","").strip().lower() in ("1","true","yes","on")),
                "WSGI_BRIDGE_INDEX": override,
                "resolved_index": resolved,
                "resolved_size": size,
                "resolved_sha256": sha256,
                "resolved_has_pastel_token": pastel,
            }
            body = json.dumps(data, default=str).encode("utf-8")
            headers = [("Content-Type","application/json; charset=utf-8"),
                       ("Content-Length","0" if method=="HEAD" else str(len(body)))]
            start_response("200 OK", headers)
            return [b"" if method=="HEAD" else body]

        # --- forzar raíz desde el bridge si se pide explícitamente ---
        try:
            force = ( __import__("os").getenv("FORCE_BRIDGE_INDEX","").strip().lower() in ("1","true","yes","on") )
        except Exception:
            force = False
        if force and path in ("/","/index.html") and method in ("GET","HEAD"):
            status, headers, body = _serve_index_html()
            # asegurar no-store y marcar fuente
            headers = [(k,v) for (k,v) in headers if k.lower()!="cache-control"]
            headers += [
                ("Cache-Control","no-store, no-cache, must-revalidate, max-age=0"),
                ("X-Index-Source","bridge"),
            ]
            return _finish(start_response, status, headers, body, method)

        return self.inner(environ, start_response)
"""
    changed = True

# 2) envolver app al final (una sola vez)
if "app = _RootBridgeAndDiag(app)" not in s:
    s += r"""

# --- aplicar wrapper de raíz/diag como capa más externa ---
app = _RootBridgeAndDiag(app)
"""
    changed = True

if changed:
    P.write_text(s, encoding="utf-8")
    print("patched: wrapper raíz + diag añadido y aplicado")
else:
    print("no changes")
