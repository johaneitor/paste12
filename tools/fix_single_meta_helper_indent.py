#!/usr/bin/env python3
import re, pathlib, sys, shutil, py_compile

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)

src = W.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n").replace("\r","\n")
src = src.replace("\t", "    ")

bak = W.with_suffix(".single_meta_fix.bak")
if not bak.exists():
    shutil.copyfile(W, bak)

def canon(indent=""):
    return (
        f"{indent}def _inject_single_meta(body):\n"
        f"{indent}    try:\n"
        f"{indent}        b = body if isinstance(body,(bytes,bytearray)) else (body or b\"\")\n"
        f"{indent}        if b and b\"<meta name=\\\"p12-single\\\"\" not in b:\n"
        f"{indent}            return b.replace(b\"<head\", b\"<head><meta name=\\\"p12-single\\\" content=\\\"1\\\">\", 1)\n"
        f"{indent}    except Exception:\n"
        f"{indent}        pass\n"
        f"{indent}    return body\n"
    )

changed = False

# Reemplaza si existe con bloque (aunque vacío)
pat_block = re.compile(r'(?ms)^(?P<i>[ ]*)def[ ]+_inject_single_meta\s*\(\s*body\s*\)\s*:\s*\n(?P<b>(?:\1[ ]+.*\n)*)')
m = pat_block.search(src)
if m:
    i = m.group('i')
    src = src[:m.start()] + canon(i) + src[m.end():]
    changed = True
else:
    # Si existe "def …:" sin cuerpo, lo inserta
    pat_bare = re.compile(r'(?m)^(?P{i}[ ]*)def[ ]+_inject_single_meta\s*\(\s*body\s*\)\s*:\s*$'.format(i='i'))
    m2 = pat_bare.search(src)
    if m2:
        i = m2.group('i')
        src = src[:m2.start()] + canon(i) + src[m2.end():]
        changed = True
    else:
        # No existe: insertarlo tras _finish o al final
        m3 = re.search(r'(?m)^def[ ]+_finish\(', src)
        ins_idx = src.find("\n", m3.end())+1 if m3 else len(src)
        src = src[:ins_idx] + canon("") + ("\n" if not src.endswith("\n") else "") + src[ins_idx:]
        changed = True

if changed:
    W.write_text(src, encoding="utf-8")

try:
    py_compile.compile(str(W), doraise=True)
    print("✓ fixed _inject_single_meta y compiló OK | backup=", bak.name)
except Exception as e:
    print("✗ compile aún falla:", e)
    import traceback
    tb = traceback.format_exc()
    mm = re.search(r'__init__\.py, line (\d+)', tb)
    if mm:
        ln = int(mm.group(1))
        ctx = src.splitlines()
        a = max(1, ln-20); b = min(len(ctx), ln+20)
        print(f"\n--- Contexto {a}-{b} ---")
        for k in range(a, b+1):
            print(f"{k:5d}: {ctx[k-1]}")
    sys.exit(1)
