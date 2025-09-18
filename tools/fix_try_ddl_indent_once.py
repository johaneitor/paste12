#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ wsgiapp/__init__.py no existe"); sys.exit(2)

# normaliza saltos de línea y tabs
s = W.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n")
if "\t" in s:
    s = s.replace("\t","    ")

lines = s.split("\n")
n = len(lines)
changed = False

def indw(l: str) -> int:
    return len(l) - len(l.lstrip(" "))

def next_nonempty(i: int) -> int:
    j = i + 1
    while j < n and lines[j].strip() == "":
        j += 1
    return j

def find_ddl_end(start: int) -> int:
    # start apunta a una línea con: cx.execute(_text(""")
    opened = False
    i = start
    while i < n:
        L = lines[i]
        # toggle en """ o ''' no escapadas
        for _ in re.finditer(r'(?<!\\)(?:"""|\'\'\')', L):
            opened = not opened
        # fuera de triple comillas, buscamos el ')))'
        if not opened:
            if re.search(r'\)\)\)\s*$', L):
                return i + 1
            if i + 1 < n and re.search(r'^\s*\)\)\)\s*$', lines[i + 1]):
                return i + 2
        i += 1
    return start + 1

i = 0
while i < n:
    L = lines[i]
    if re.match(r'^\s*try:\s*$', L):
        base = indw(L)
        j = next_nonempty(i)
        if j < n and indw(lines[j]) <= base and 'cx.execute(_text("""' in lines[j]:
            start = j
            end = find_ddl_end(start)
            # indentar todo el bloque DDL bajo el try (4 espacios más)
            for k in range(start, min(end, n)):
                lines[k] = (" " * (base + 4)) + lines[k].lstrip(" ")
            changed = True
            i = end
            continue
    i += 1

out = "\n".join(lines)
if changed:
    bak = W.with_suffix(".py.fix_try_ddl_indent_once.bak")
    if not bak.exists():
        shutil.copyfile(W, bak)
    W.write_text(out, encoding="utf-8")
    print(f"patched: indent DDL under try | backup={bak.name}")
else:
    print("OK: nada que indentar")

# Gate de compilación con ventana de contexto si falla
try:
    py_compile.compile(str(W), doraise=True)
    print("✓ py_compile OK")
except Exception as e:
    print("✗ py_compile falla:", e)
    tb = traceback.format_exc()
    m = re.search(r'__init__\.py, line (\d+)', tb)
    if m:
        ln = int(m.group(1))
        txt = W.read_text(encoding="utf-8").splitlines()
        a = max(1, ln-30); b = min(len(txt), ln+30)
        print(f"\n--- Ventana {a}-{b} ---")
        for k in range(a, b+1):
            print(f"{k:5d}: {txt[k-1]}")
    sys.exit(1)
