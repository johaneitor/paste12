#!/usr/bin/env python3
import re, pathlib, shutil, py_compile, sys

W = pathlib.Path("wsgiapp/__init__.py")
s = W.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n").replace("\r","\n")
bak = W.with_suffix(".call_single_meta.bak")
if not bak.exists():
    shutil.copyfile(W, bak)

# Si ya hay una llamada cercana, no hacer nada
if re.search(r'(?m)^[ \t]*body\s*=\s*_inject_single_meta\(body\)', s):
    print("OK: ya llama a _inject_single_meta(body)")
else:
    # Buscamos la asignación 'body = _b' del bloque que inyecta data-single
    pat = re.compile(r'(?m)^([ \t]*)body\s*=\s*_b\s*$')
    def add_after(m):
        indent = m.group(1)
        return m.group(0) + "\n" + f"{indent}body = _inject_single_meta(body)"
    s2, n = pat.subn(add_after, s, count=1)
    if n == 0:
        print("✗ no encontré 'body = _b' para colgar la llamada; revisa el archivo"); sys.exit(1)
    s = s2
    W.write_text(s, encoding="utf-8")
    print("patched: agregada llamada a _inject_single_meta(body) | backup=", bak.name)

try:
    py_compile.compile(str(W), doraise=True)
    print("✓ py_compile OK")
except Exception as e:
    print("✗ py_compile FAIL:", e); sys.exit(1)
