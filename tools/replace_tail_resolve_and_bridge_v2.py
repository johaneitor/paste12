#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)

def R(): return W.read_text(encoding="utf-8")
def norm(s:str)->str:
    s = s.replace("\r\n","\n").replace("\r","\n")
    return s.replace("\t","    ") if "\t" in s else s

def gate():
    try:
        py_compile.compile(str(W), doraise=True)
        print("✓ py_compile OK"); return True
    except Exception as e:
        print("✗ py_compile FAIL:", e)
        tb = traceback.format_exc()
        m = re.search(r'__init__\.py, line (\d+)', tb)
        if m:
            ln = int(m.group(1))
            ctx = R().splitlines()
            a = max(1, ln-40); b = min(len(ctx), ln+40)
            print(f"\n--- Ventana {a}-{b} ---")
            for k in range(a, b+1):
                print(f"{k:5d}: {ctx[k-1]}")
        return False

s = norm(R())

# 1) Localiza la cola a partir de la primera aparición top/indented de: _app = _resolve_app()
m_start = re.search(r'(?m)^[ ]*_app\s*=\s*_resolve_app\(\)\s*$', s)
if not m_start:
    print("✗ no hallé ancla '_app = _resolve_app()'"); sys.exit(1)

start = m_start.start()

# 2) Construye cola canónica (top-level, sin indent roto)
TAIL = '''
_app = _resolve_app()
app  = _middleware(_app, is_fallback=(_app is None))
# Intenta aplicar un root middleware externo si existe
try:
    _root_force_mw  # noqa: F821
except NameError:
    pass
else:
    try:
        app = _root_force_mw(app)
    except Exception:
        pass

# --- middleware final: fuerza '/' desde el bridge si FORCE_BRIDGE_INDEX está activo ---
def _root_force_mw(inner):
    import os
    def _mw(environ, start_response):
        path   = environ.get("PATH_INFO", "") or ""
        method = (environ.get("REQUEST_METHOD", "GET") or "GET").upper()
        _force = os.getenv("FORCE_BRIDGE_INDEX","").strip().lower() in ("1","true","yes","on")
        if _force and path in ("/","/index.html") and method in ("GET","HEAD"):
            status, headers, body = _serve_index_html()
            # Garantizar no-store y marcar fuente
            headers = [(k, v) for (k, v) in headers if k.lower() != "cache-control"]
            headers += [
                ("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0"),
                ("X-Index-Source", "bridge"),
            ]
            return _finish(start_response, status, headers, body, method)
        return inner(environ, start_response)
    return _mw

class _ForceRootIndexWrapper:
    def __init__(self, inner):
        self.inner = inner
    def __call__(self, environ, start_response):
        return _root_force_mw(self.inner)(environ, start_response)
'''.lstrip("\n")

# 3) Reemplaza TODO desde el ancla hasta EOF
new_s = s[:start] + TAIL
if new_s == s:
    print("OK: no cambios (ya estaba canónico)")
    if not gate(): sys.exit(1)
    sys.exit(0)

bak = W.with_suffix(".py.replace_tail_bridge_v2.bak")
if not bak.exists():
    shutil.copyfile(W, bak)
W.write_text(new_s, encoding="utf-8")
print(f"patched: cola (_resolve_app → EOF) reescrita | backup={bak.name}")

if not gate(): sys.exit(1)
