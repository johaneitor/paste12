#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ wsgiapp/__init__.py no existe"); sys.exit(2)

raw = W.read_text(encoding="utf-8")
s = raw.replace("\r\n","\n").replace("\r","\n")
if "\t" in s: s = s.replace("\t","    ")
changed = s != raw

# A) asegurar exactamente 1 import top-level (dejamos el primero y borramos duplicados tope)
top_import_re = re.compile(r'(?m)^\s*import\s+json\s+as\s+_json_mod\s*$')
top_imports = list(top_import_re.finditer(s))

if not top_imports:
    # no hay import en el archivo → insertamos al inicio (tras docstring si existe)
    mdoc = re.match(r'\s*(\"\"\"[\s\S]*?\"\"\"|\'\'\'[\s\S]*?\'\'\')\s*\n', s)
    ins = "import json as _json_mod\n"
    if mdoc:
        pos = mdoc.end()
        s = s[:pos] + ins + s[pos:]
    else:
        s = ins + s
    changed = True
    top_imports = list(top_import_re.finditer(s))

# eliminar imports duplicados extra (dejamos el primero)
if len(top_imports) > 1:
    # conservar el primero por orden textual
    keep0 = top_imports[0].span()
    # borrar los subsiguientes
    new = []
    last = 0
    for i, m in enumerate(top_imports):
        a, b = m.span()
        if i == 0:
            continue
        new.append(s[last:a])
        last = b
    new.append(s[last:])
    s = "".join(new)
    changed = True

# B) eliminar bloques “fantasma”:
# patrón: (top-level) import json as _json_mod \n  <líneas indentadas> … que contengan body = _json_mod.dumps
lines = s.split("\n")
i = 0
out = []
removed_blocks = 0
n = len(lines)

def is_top(line: str) -> bool:
    return len(line) - len(line.lstrip(" ")) == 0

while i < n:
    ln = lines[i]
    if is_top(ln) and re.match(r'^import\s+json\s+as\s+_json_mod\s*$', ln):
        # mirar hacia adelante: si la(s) próxima(s) línea(s) están indentadas y contienen body/start_response/return [body]
        j = i + 1
        saw_indented = False
        saw_body = False
        saw_start = False
        saw_return = False
        while j < n:
            l2 = lines[j]
            if l2.strip() == "":
                j += 1
                continue
            if is_top(l2):
                break  # fin del bloque indentado
            saw_indented = True
            if "body = _json_mod.dumps(" in l2: saw_body = True
            if "start_response(" in l2: saw_start = True
            if "return [body]" in l2: saw_return = True
            j += 1
        if saw_indented and (saw_body or saw_start or saw_return):
            # eliminar desde i..j-1 (import + bloque indentado)
            removed_blocks += 1
            i = j
            changed = True
            continue
        else:
            # no es un bloque fantasma, conservar
            out.append(ln); i += 1; continue
    else:
        out.append(ln); i += 1

s2 = "\n".join(out)
if s2 != s:
    s = s2
    changed = True

# C) guardar + backup + gate
if changed:
    bak = W.with_suffix(".py.scrub_json_tail.bak")
    if not bak.exists():
        shutil.copyfile(W, bak)
    W.write_text(s, encoding="utf-8")
    print(f"patched: scrub stray json tail (removed_blocks={removed_blocks}) | backup={bak.name}")
else:
    print("OK: nada que limpiar")

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
