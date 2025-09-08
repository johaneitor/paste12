#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)

src = W.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n")

if "app = _root_force_mw(app)" in src:
    print("OK: hook CORS ya presente"); 
    py_compile.compile(str(W), doraise=True); print("✓ py_compile OK"); sys.exit(0)

m = re.search(r'(?m)^app\s*=\s*_middleware\([^)]*\)\s*#?.*$', src)
if not m:
    print("✗ no hallé 'app = _middleware(...)' para anclar el hook"); sys.exit(1)

injection = r'''
try:
    _root_force_mw  # noqa
except NameError:
    pass
else:
    try:
        app = _root_force_mw(app)
    except Exception:
        pass
'''.lstrip("\n")

insert_at = m.end()
new = src[:insert_at] + "\n" + injection + src[insert_at:]

bak = W.with_suffix(".py.ensure_cors_hook.bak")
if not bak.exists():
    shutil.copyfile(W, bak)
W.write_text(new, encoding="utf-8")
print(f"patched: hook CORS aplicado detrás de app=_middleware | backup={bak.name}")

py_compile.compile(str(W), doraise=True)
print("✓ py_compile OK")
