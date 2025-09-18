#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)

def norm(s: str) -> str:
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
            ctx = W.read_text(encoding="utf-8").splitlines()
            a = max(1, ln-40); b = min(len(ctx), ln+40)
            print(f"\n--- Ventana {a}-{b} ---")
            for k in range(a, b+1):
                print(f"{k:5d}: {ctx[k-1]}")
        return False

s = norm(W.read_text(encoding="utf-8"))
pat_if = re.compile(r'^([ ]*)if\s+inner_app\s+is\s+not\s+None\s*:\s*$', re.M)
m = pat_if.search(s)
if not m:
    print("✗ no encontré 'if inner_app is not None:'"); sys.exit(1)

base_ws = m.group(1)
base = len(base_ws)

lines = s.split("\n")
# índice (0-based) de la línea del if
if_idx = s[:m.start()].count("\n")
# buscar la primera línea no vacía después del if
j = if_idx + 1
while j < len(lines) and lines[j].strip() == "":
    j += 1
if j >= len(lines):
    print("✗ no hay cuerpo tras el if"); sys.exit(1)

body = lines[j]
# si el cuerpo no está más indentado, lo indentamos a base+4
if len(body) - len(body.lstrip(" ")) <= base:
    new_line = base_ws + "    " + body.lstrip(" ")
    lines[j] = new_line

out = "\n".join(lines)
if out == s:
    print("OK: no cambios aplicados (indent ya correcto)")
    if not gate(): sys.exit(1)
    sys.exit(0)

bak = W.with_suffix(".py.fix_inner_app_return_indent.bak")
if not bak.exists():
    shutil.copyfile(W, bak)
W.write_text(out, encoding="utf-8")
print(f"patched: indent de 'return inner_app(...)' fijado | backup={bak.name}")

if not gate(): sys.exit(1)
