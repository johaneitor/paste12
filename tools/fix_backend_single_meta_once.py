#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)

src = W.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n").replace("\r","\n")
src = src.replace("\t","    ")
bak = W.with_suffix(".single_meta_hotfix.bak")
if not bak.exists():
    shutil.copyfile(W, bak)

def canon(indent=""):
    return (
f"""{indent}def _inject_single_meta(body):
{indent}    try:
{indent}        b = body if isinstance(body,(bytes,bytearray)) else (body or b"")
{indent}        if b and b"<meta name=\\"p12-single\\"" not in b:
{indent}            return b.replace(b"<head", b"<head><meta name=\\"p12-single\\" content=\\"1\\">", 1)
{indent}    except Exception:
{indent}        pass
{indent}    return body
"""
    )

changed = False

# 1) Normalizar/crear helper con cuerpo (mata definiciones vacías o con indent raro)
m_full = re.search(r'(?ms)^([ ]*)def[ ]+_inject_single_meta\s*\(\s*body\s*\)\s*:\s*(?:\n((?:\1[ ]+.*\n)+))?', src)
if m_full:
    indent = m_full.group(1)
    src = src[:m_full.start()] + canon(indent) + src[m_full.end():]
    changed = True
else:
    # Buscar def sin cuerpo explícito
    m_head = re.search(r'(?m)^([ ]*)def[ ]+_inject_single_meta\s*\(\s*body\s*\)\s*:\s*$', src)
    if m_head:
        indent = m_head.group(1)
        ins_at = m_head.end()
        src = src[:ins_at] + "\n" + canon(indent) + src[ins_at:]
        changed = True
    else:
        # Insertar helper cerca de _finish (si existe) o al inicio del módulo
        m_finish = re.search(r'(?m)^def[ ]+_finish\s*\(', src)
        ins_at = src.find("\n", m_finish.end())+1 if m_finish else 0
        src = src[:ins_at] + canon("") + src[ins_at:]
        changed = True

# 2) Asegurar llamada tras "body = _b" del bloque de single-by-id (idempotente)
if not re.search(r'(?m)^[ ]*body[ ]*=[ ]*_inject_single_meta\(body\)', src):
    pat_body_assign = re.compile(r'(?m)^([ ]*)body[ ]*=[ ]*_b[ ]*$')
    def add_after(m):
        i = m.group(1) or ""
        return m.group(0) + "\n" + f"{i}body = _inject_single_meta(body)"
    src2, n = pat_body_assign.subn(add_after, src, count=1)
    if n > 0:
        src = src2
        changed = True

# 3) Guardar si hubo cambios
if changed:
    W.write_text(src, encoding="utf-8")

# 4) Gate de compilación con contexto si falla
try:
    py_compile.compile(str(W), doraise=True)
    print("✓ single_meta helper OK y compiló | backup=", bak.name)
except Exception as e:
    print("✗ py_compile FAIL:", e)
    tb = traceback.format_exc()
    mm = re.search(r'__init__\.py, line (\d+)', tb)
    if mm:
        ln = int(mm.group(1)); ctx = src.splitlines()
        a = max(1, ln-20); b = min(len(ctx), ln+20)
        print(f"\n--- Contexto {a}-{b} ---")
        for k in range(a, b+1):
            print(f"{k:5d}: {ctx[k-1]}")
    sys.exit(1)
