#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ wsgiapp/__init__.py no existe"); sys.exit(2)

def rnorm():
    s = W.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n")
    if "\t" in s: s = s.replace("\t","    ")
    return s

def gate():
    try:
        py_compile.compile(str(W), doraise=True)
        return True, ""
    except Exception as e:
        return False, traceback.format_exc()

s = rnorm()
lines = s.split("\n")
n = len(lines)
changed = False

def indw(l:str)->int: return len(l) - len(l.lstrip(" "))

i = 0
while i < n:
    ln = lines[i]
    m = re.match(r'^([ ]*)(except\b.*:|finally\s*:)\s*$', ln)
    if not m:
        i += 1
        continue
    base_ws = m.group(1)
    base = len(base_ws)

    # Busca hacia atrás un 'try:' con el MISMO indent
    k = i - 1
    has_try = False
    while k >= 0:
        prev = lines[k]
        if prev.strip() == "" or prev.lstrip().startswith("#"):
            k -= 1
            continue
        curw = indw(prev)
        if curw < base:
            # ya saltamos a un bloque menos indentado → no hay try válido
            break
        if curw == base and re.match(r'^\s*try:\s*$', prev):
            has_try = True
            break
        k -= 1

    if not has_try:
        # Inserta un try con cuerpo 'pass' justo antes del except/finally
        lines.insert(i, base_ws + "try:")
        lines.insert(i+1, base_ws + "    pass")
        n += 2
        changed = True
        i += 2  # saltar lo recién insertado para no re-procesarlo
        continue

    i += 1

if changed:
    bak = W.with_suffix(".py.fix_orphan_except.bak")
    if not bak.exists():
        shutil.copyfile(W, bak)
    W.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"patched: orphan except/finally healed | backup={bak.name}")
else:
    print("OK: no orphan except/finally found")

ok, tb = gate()
if ok:
    print("✓ py_compile OK")
    sys.exit(0)

print("✗ py_compile falla:", tb)
m = re.search(r'__init__\.py, line (\d+)', tb)
if m:
    ln = int(m.group(1))
    ctx = rnorm().splitlines()
    a = max(1, ln-30); b = min(len(ctx), ln+30)
    print(f"\n--- Ventana {a}-{b} ---")
    for j in range(a, b+1):
        print(f"{j:5d}: {ctx[j-1]}")
sys.exit(1)
