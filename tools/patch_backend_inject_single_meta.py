#!/usr/bin/env python3
import re, pathlib, sys, py_compile, shutil

W = pathlib.Path("wsgiapp/__init__.py")
src = W.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n").replace("\r","\n")

bak = W.with_suffix(".inject_single_meta.bak")
if not bak.exists():
    shutil.copyfile(W, bak)

changed = False

# 1) Helper a nivel módulo (si falta)
if "_inject_single_meta(" not in src:
    helper = '''
def _inject_single_meta(body):
    try:
        b = body if isinstance(body,(bytes,bytearray)) else (body or b"")
        if b and b"<meta name=\\"p12-single\\"" not in b:
            # Insertar justo tras <head
            return b.replace(b"<head", b"<head><meta name=\\"p12-single\\" content=\\"1\\">", 1)
    except Exception:
        pass
    return body
'''.lstrip("\n")
    m = re.search(r'(?m)^def[ ]+_finish\(', src)
    if m:
        p = src.find("\n", m.end())
        src = src[:p+1] + helper + src[p+1:]
    else:
        src = src + "\n" + helper
    changed = True

# 2) Donde ya se llama _inject_single_attr(...) encadenar _inject_single_meta(...)
def add_meta_after_attr(block: str) -> str:
    if "_inject_single_attr(" in block and "_inject_single_meta(" not in block:
        block = re.sub(
            r'(body[ ]*=[ ]*_inject_single_attr\([^)]*\)\s*)',
            r'\1\n            body = _inject_single_meta(body)\n',
            block, count=1)
    return block

# Buscar el bloque de "/" ó "/index.html"
pat = re.compile(
    r'(?ms)^([ ]*)if[ ]+path[ ]+in[ ]*\(\s*"/",\s*"/index\.html"\s*\)[ ]+and[ ]+method[ ]+in[ ]*\(\s*"GET","HEAD"\s*\)\s*:\s*'
    r'(.*?)'
    r'(?:^|\n)[ ]*return[ ]+_finish\([^)]*\)',
)
def repl(m):
    lead, body = m.group(1), m.group(2)
    new_body = add_meta_after_attr(body)
    return m.group(0).replace(body, new_body)

src2, n = pat.subn(repl, src, count=1)
if n > 0 and src2 != src:
    src = src2
    changed = True

if not changed:
    print("OK: nothing to patch (ya estaba meta o no se halló patrón).")
else:
    W.write_text(src, encoding="utf-8")

py_compile.compile(str(W), doraise=True)
print("✓ backend: meta p12-single inyectada | backup=", bak.name)
