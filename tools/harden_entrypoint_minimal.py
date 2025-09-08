#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)

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
            ctx = W.read_text(encoding="utf-8").splitlines()
            a = max(1, ln-35); b = min(len(ctx), ln+35)
            print(f"\n--- Ventana {a}-{b} ---")
            for k in range(a, b+1):
                print(f"{k:5d}: {ctx[k-1]}")
        return False

src = W.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n")

# Si ya existe 'try: app\nexcept NameError:' guard final, no dupliques
if re.search(r'(?ms)try:\s*app\s*\n\s*except\s+NameError\s*:', src):
    print("OK: ya existe guard final de 'app' (no cambios)")
    if not gate(): sys.exit(1)
    sys.exit(0)

GUARD = r'''
# --- Guard final: garantiza que 'app' exista a nivel módulo ---
try:
    app  # noqa: F821
except NameError:
    try:
        _app = _resolve_app()  # type: ignore[name-defined]
    except Exception:
        _app = None
    try:
        app = _middleware(_app, is_fallback=(_app is None))  # type: ignore[name-defined]
    except Exception:
        # Fallback mínimo y seguro (sirve health y 404 JSON)
        def app(environ, start_response):  # type: ignore[no-redef]
            path = (environ.get("PATH_INFO") or "")
            if path == "/api/health":
                start_response("200 OK", [("Content-Type","application/json; charset=utf-8")])
                return [b'{"ok": true}']
            start_response("404 Not Found", [("Content-Type","application/json; charset=utf-8")])
            return [b'{"ok": false, "error": "not_found"}']
'''.lstrip("\n")

new = src.rstrip() + "\n\n" + GUARD
bak = W.with_suffix(".py.harden_entrypoint_min.bak")
if not bak.exists():
    shutil.copyfile(W, bak)
W.write_text(new, encoding="utf-8")
print(f"patched: guard final de entrypoint añadido | backup={bak.name}")

if not gate(): sys.exit(1)
