#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ wsgiapp/__init__.py no existe"); sys.exit(2)

def norm(s:str)->str:
    s = s.replace("\r\n","\n").replace("\r","\n")
    if "\t" in s: s = s.replace("\t","    ")
    return s

s = norm(W.read_text(encoding="utf-8"))
lines = s.split("\n")
n = len(lines)
changed = False

def indw(l:str)->int: return len(l) - len(l.lstrip(" "))
def next_nonempty(i:int)->int:
    j = i+1
    while j < n and lines[j].strip()=="":
        j += 1
    return j

# headers a verificar
hdr = re.compile(r'^(except\b.*:|finally:|try:|else:|elif\b.*:)\s*$')

i = 0
while i < n:
    L = lines[i]
    if hdr.match(L.lstrip()):
        base = indw(L)
        body_i = next_nonempty(i)
        # EOF: inserta cuerpo mínimo
        if body_i >= n:
            lines.append(" "*(base+4) + "pass")
            n += 1; changed = True
            i += 1
            continue
        body = lines[body_i]
        # Si otro header al mismo/menor indent => cuerpo faltante
        if indw(body) <= base and hdr.match(body.lstrip()):
            lines.insert(body_i, " "*(base+4) + "pass")
            n += 1; changed = True
            i = body_i + 1
            continue
        # Si el “cuerpo” no está más indentado => reindent
        if indw(body) <= base:
            lines[body_i] = " "*(base+4) + body.lstrip(" ")
            changed = True
            i = body_i + 1
            continue
    i += 1

out = "\n".join(lines)
if changed:
    bak = W.with_suffix(".py.fix_except_indent_hard.bak")
    if not bak.exists(): shutil.copyfile(W, bak)
    W.write_text(out, encoding="utf-8")
    print(f"patched: except/finally/try/else/elif con cuerpo normalizado | backup={bak.name}")
else:
    print("OK: no headers con cuerpo defectuoso")

# Gate + ventana si falla
try:
    py_compile.compile(str(W), doraise=True)
    print("✓ py_compile OK")
except Exception as e:
    print("✗ py_compile falla:", e)
    tb = traceback.format_exc()
    m = re.search(r'__init__\.py, line (\d+)', tb)
    if m:
        ln = int(m.group(1))
        ctx = out.splitlines()
        a = max(1, ln-30); b = min(len(ctx), ln+30)
        print(f"\n--- Ventana {a}-{b} ---")
        for k in range(a, b+1):
            print(f"{k:5d}: {ctx[k-1]}")
    sys.exit(1)
