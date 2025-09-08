#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ wsgiapp/__init__.py no existe"); sys.exit(2)

def norm(s:str)->str:
    s = s.replace("\r\n","\n").replace("\r","\n")
    if "\t" in s: s = s.replace("\t","    ")
    return s

def indw(line:str)->int:
    return len(line) - len(line.lstrip(" "))

s = norm(W.read_text(encoding="utf-8"))
lines = s.split("\n")
n = len(lines)

changed = False
i = 0
while i < n:
    ln = lines[i]
    m = re.match(r'^([ ]*)try:\s*$', ln)
    if not m:
        i += 1
        continue
    base_ws = m.group(1)
    base_w  = len(base_ws)

    # j: primera línea del cuerpo (salta líneas vacías)
    j = i + 1
    while j < n and lines[j].strip() == "":
        j += 1

    # k: primer índice con indentación <= base_w (o fin)
    k = j
    has_handler = False
    while k < n:
        cur = lines[k]
        if cur.strip() == "":
            k += 1
            continue
        w = indw(cur)
        # ¿aparece un handler al mismo nivel?
        if w == base_w and re.match(r'^(except\b|finally\b)', cur.lstrip()):
            has_handler = True
            break
        # ¿cierra bloque? (dedent <= base y no es un handler)
        if w <= base_w:
            break
        k += 1

    if has_handler:
        # ya está bien ese try:
        i = k + 1
        continue

    # Insertar handler antes de la dedent (línea k) o al final si EOF
    ins_at = k if k < n else n
    lines.insert(ins_at, base_ws + "except Exception:")
    lines.insert(ins_at + 1, base_ws + "    pass")
    n += 2
    changed = True

    # saltar más allá de lo insertado
    i = ins_at + 2

out = "\n".join(lines)
if changed:
    bak = W.with_suffix(".py.fix_all_try_blocks_v1.bak")
    if not bak.exists():
        shutil.copyfile(W, bak)
    W.write_text(out, encoding="utf-8")
    print(f"patched: try-block handlers insertados | backup={bak.name}")
else:
    print("OK: no había try sin except/finally")

# Gate de compilación
try:
    py_compile.compile(str(W), doraise=True)
    print("✓ py_compile OK")
except Exception as e:
    print("✗ py_compile falla:", e)
    tb = traceback.format_exc()
    m = re.search(r'__init__\.py, line (\d+)', tb)
    if m:
        ln = int(m.group(1))
        L = W.read_text(encoding="utf-8").splitlines()
        start = max(1, ln-25); end = min(len(L), ln+25)
        print(f"\n--- Ventana {start}-{end} ---")
        for k in range(start, end+1):
            print(f"{k:5d}: {L[k-1]}")
    sys.exit(1)
