#!/usr/bin/env python3
import pathlib, py_compile

P = pathlib.Path("wsgiapp/__init__.py")
s = P.read_text(encoding="utf-8")
changed = False

# Asegura imports mínimos
if "import os" not in s:  s = "import os\n"  + s; changed = True
if "import json" not in s: s = "import json\n" + s; changed = True

if "class _DeployStampGuard" not in s:
    s += r"""

# === APPEND-ONLY: Guard para /api/deploy-stamp (a prueba de fallos) ===
class _DeployStampGuard:
    def __init__(self, inner):
        self.inner = inner

    def __call__(self, environ, start_response):
        try:
            path   = (environ.get("PATH_INFO") or "")
            method = (environ.get("REQUEST_METHOD") or "GET").upper()
            if method == "GET" and path == "/api/deploy-stamp":
                commit = (os.environ.get("RENDER_GIT_COMMIT")
                          or os.environ.get("COMMIT")
                          or os.environ.get("GIT_COMMIT")
                          or "")
                # Intentamos leer .deploystamp si existe
                stamp = ""
                try:
                    import pathlib
                    f = pathlib.Path(".deploystamp")
                    if f.exists():
                        stamp = f.read_text(encoding="utf-8").strip()
                except Exception:
                    pass
                body = json.dumps({"ok": True, "commit": commit, "stamp": stamp}).encode("utf-8")
                start_response("200 OK", [
                    ("Content-Type","application/json; charset=utf-8"),
                    ("Content-Length", str(len(body))),
                    ("X-WSGI-Bridge","1"),
                ])
                return [body]
        except Exception:
            # si algo pasa, seguimos al inner
            pass
        return self.inner(environ, start_response)
"""
    changed = True

if "DEPLOYSTAMP_GUARD_WRAPPED = True" not in s:
    s += r"""
# --- envolver outermost: deploy-stamp guard ---
try:
    DEPLOYSTAMP_GUARD_WRAPPED
except NameError:
    try:
        app = _DeployStampGuard(app)
    except Exception:
        pass
    DEPLOYSTAMP_GUARD_WRAPPED = True
"""
    changed = True

if not changed:
    print("OK: deploy-stamp guard ya estaba"); raise SystemExit(0)

P.write_text(s, encoding="utf-8")
py_compile.compile(str(P), doraise=True)
print("patched: deploy-stamp guard")
