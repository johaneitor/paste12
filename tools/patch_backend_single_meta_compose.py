#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile

W = pathlib.Path("wsgiapp/__init__.py")
src = W.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n").replace("\r","\n")

bak = W.with_suffix(".singlemeta_v3.bak")
if not bak.exists():
    shutil.copyfile(W, bak)

changed = False

# 1) Helper idempotente
if "_inject_single_meta(" not in src:
    helper = '''
def _inject_single_meta(body):
    try:
        b = body if isinstance(body, (bytes, bytearray)) else (body or b"")
        if b and (b.find(b'name="p12-single"') == -1):
            return b.replace(b"<head", b"<head><meta name=\\"p12-single\\" content=\\"1\\">", 1)
    except Exception:
        pass
    return body
'''
    # lo insertamos justo después de _inject_single_attr si existe; si no, tras _finish; si no, al final
    pos = -1
    m = re.search(r'(?m)^def[ ]+_inject_single_attr\(', src)
    if m:
        pos = src.find("\n", m.end()) + 1
    else:
        m = re.search(r'(?m)^def[ ]+_finish\(', src)
        if m:
            pos = src.find("\n", m.end()) + 1
    if pos == -1:
        src = src + "\n" + helper
    else:
        src = src[:pos] + helper + src[pos:]
    changed = True

# 2) Componer la llamada: _inject_single_attr(...) -> _inject_single_meta(_inject_single_attr(...))
pat = re.compile(r'(?m)^[ \t]*body[ ]*=[ ]*_inject_single_attr\(\s*body\s*,\s*_idv\[0\]\s*\)')
if pat.search(src) and "_inject_single_meta(_inject_single_attr(body, _idv[0]))" not in src:
    src = pat.sub("            body = _inject_single_meta(_inject_single_attr(body, _idv[0]))", src)
    changed = True

# 3) Guardar y compilar
if changed:
    W.write_text(src, encoding="utf-8")
try:
    py_compile.compile(str(W), doraise=True)
    print("✓ single-meta compose aplicado | backup=", bak.name if bak.exists() else "(none)")
except Exception as e:
    print("✗ py_compile FAIL:", e)
    # revertir si rompimos algo
    if bak.exists():
        shutil.copyfile(bak, W)
    sys.exit(1)
