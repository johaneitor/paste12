import pathlib

P = pathlib.Path("wsgiapp/__init__.py")
s = P.read_text(encoding="utf-8")

if "class _BridgeDiagWrapper" in s:
    print("ya estaba inyectado")
else:
    s += r"""

# === APPEND-ONLY: diagnóstico del bridge en /api/bridge-state ===
class _BridgeDiagWrapper:
    def __init__(self, inner):
        self.inner = inner

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO","") or "")
        method = (environ.get("REQUEST_METHOD","GET") or "GET").upper()

        if path == "/api/bridge-state":
            import os, json, hashlib, os as _os
            # Variables de entorno relevantes
            force_env  = os.getenv("FORCE_BRIDGE_INDEX","")
            force_bool = force_env.strip().lower() in ("1","true","yes","on")
            override   = os.environ.get("WSGI_BRIDGE_INDEX") or ""

            # Resolver repo y candidatos a index
            try:
                _REPO_DIR2 = _os.path.dirname(_os.path.dirname(_os.path.abspath(__file__)))
            except Exception:
                _REPO_DIR2 = ""

            cands = [override] if override else [
                _os.path.join(_REPO_DIR2, "backend", "static", "index.html"),
                _os.path.join(_REPO_DIR2, "public",  "index.html"),
                _os.path.join(_REPO_DIR2, "frontend","index.html"),
                _os.path.join(_REPO_DIR2, "index.html"),
            ]

            resolved = None; size = None; sha256 = None; pastel = False
            try:
                for pth in cands:
                    if pth and _os.path.isfile(pth):
                        resolved = pth
                        size = _os.path.getsize(pth)
                        with open(pth,"rb") as f:
                            data = f.read()
                        sha256 = hashlib.sha256(data).hexdigest()
                        pastel = (b'--teal:#8fd3d0' in data)
                        break
            except Exception:
                pass

            data = {
                "ok": True,
                "force_env": force_env,
                "force_bool": force_bool,
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

        return self.inner(environ, start_response)

# envolver como outermost
app = _BridgeDiagWrapper(app)
"""
    P.write_text(s, encoding="utf-8")
    print("patched: /api/bridge-state añadido y app envuelta")
