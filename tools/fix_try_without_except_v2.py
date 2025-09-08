#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ wsgiapp/__init__.py no existe"); sys.exit(2)

raw = W.read_text(encoding="utf-8")
s = raw.replace("\r\n","\n").replace("\r","\n")
if "\t" in s: s = s.replace("\t","    ")

lines = s.split("\n")
changed = False

def indent_width(line: str) -> int:
    return len(line) - len(line.lstrip(" "))

# Acepta 'try:' con comentarios:  try:  # foo
try_re = re.compile(r'^([ ]*)try:\s*(?:#.*)?$')
i = 0
while i < len(lines):
    ln = lines[i]
    m = try_re.match(ln)
    if not m:
        i += 1
        continue

    base = m.group(1)
    base_w = len(base)

    # Avanza al primer no-vacío después del 'try:'
    j = i + 1
    while j < len(lines) and lines[j].strip() == "":
        j += 1

    # Recorre el cuerpo del try: mientras indent > base
    k = j
    while k < len(lines):
        l = lines[k]
        if l.strip() == "":
            k += 1
            continue
        cur_w = indent_width(l)
        if cur_w <= base_w:
            break
        k += 1

    # k = primera línea con indent <= base (o EOF): ahí debería venir except/finally
    if k < len(lines):
        header = lines[k].lstrip()
        if re.match(r'^(except\b|finally\b)', header):
            # Ya está correcto
            i = k + 1
            continue
        # Insertar except/pass antes de esa línea
        lines.insert(k, base + "    pass")
        lines.insert(k, base + "except Exception:")
        changed = True
        i = k + 2
    else:
        # EOF: agregar except/pass al final del archivo
        lines.append(base + "except Exception:")
        lines.append(base + "    pass")
        changed = True
        i = len(lines)

out = "\n".join(lines)
if changed:
    bak = W.with_suffix(".py.fix_try_no_except_v2.bak")
    if not bak.exists():
        shutil.copyfile(W, bak)
    W.write_text(out, encoding="utf-8")
    print(f"patched: inserted except/pass en try sin handler | backup={bak.name}")
else:
    print("OK: no bare try blocks found")

# Gate de compilación con ventana si falla
try:
    py_compile.compile(str(W), doraise=True)
    print("✓ py_compile OK")
except Exception as e:
    print("✗ py_compile falla:", e)
    tb = traceback.format_exc()
    m = re.search(r'__init__\.py, line (\d+)', tb)
    if m:
        ln = int(m.group(1))
        start = max(1, ln-25); end = ln+25
        txt = W.read_text(encoding="utf-8").splitlines()
        print(f"\n--- Ventana {start}-{end} ---")
        for k in range(start, min(end, len(txt))+1):
            print(f"{k:5d}: {txt[k-1]}")
    sys.exit(1)
