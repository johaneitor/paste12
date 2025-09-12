#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)

def R(): return W.read_text(encoding="utf-8", errors="ignore")
src = R().replace("\r\n","\n").replace("\r","\n").replace("\t","   ")
lines = src.split("\n")

bak = W.with_suffix(".py.def_bodies_single_helper.bak")
if not bak.exists():
    shutil.copyfile(W, bak)

# Bloque helper canónico (nivel módulo)
helper_block = [
    "def _inject_single_attr(body, nid):",
    "    try:",
    "        b = body if isinstance(body, (bytes, bytearray)) else (body or b\"\")",
    "        if b:",
    "            return b.replace(b\"<body\", f'<body data-single=\"1\" data-note-id=\"{nid}\"'.encode(\"utf-8\"), 1)",
    "    except Exception:",
    "        pass",
    "    return body",
    "",
]

changed = False

# 1) Quitar cualquier definición previa de _inject_single_attr y reinsertar helper canónico a nivel módulo
#    a) elimina bloques previos (aunque estén mal indentados)
pat_any_helper = re.compile(r'(?ms)^[ \t]*def[ ]+_inject_single_attr\s*\([^\)]*\)\s*:\s*.*?(?=^[^\s]|\Z)')
src = re.sub(pat_any_helper, "", src)
lines = src.split("\n")

#    b) insertar antes de _serve_index_html o al principio del archivo
insert_at = 0
for i, L in enumerate(lines):
    if re.match(r'^def\s+_serve_index_html\s*\(', L):
        insert_at = i
        break
lines[insert_at:insert_at] = helper_block
changed = True

# 2) Asegurar que TODA def tenga al menos una línea indentada de cuerpo (si no, insertar 'pass')
i = 0
while i < len(lines):
    m = re.match(r'^([ ]*)def\s+\w+\s*\(.*\)\s*:\s*$', lines[i])
    if m:
        base = len(m.group(1))
        j = i + 1
        # saltar líneas en blanco
        while j < len(lines) and lines[j].strip() == "":
            j += 1
        need_pass = False
        if j >= len(lines):
            need_pass = True
        else:
            ind = len(lines[j]) - len(lines[j].lstrip(" "))
            if ind <= base:
                need_pass = True
        if need_pass:
            lines.insert(i + 1, " " * (base + 4) + "pass")
            changed = True
            i += 1
    i += 1

out = "\n".join(lines)
if changed:
    W.write_text(out, encoding="utf-8")

# 3) Gate de compilación (con ventana si falla)
try:
    py_compile.compile(str(W), doraise=True)
    print("✓ backend: helper + cuerpos de def OK | backup=", bak.name)
except Exception as e:
    print("✗ py_compile FAIL:", e)
    tb = traceback.format_exc()
    m = re.search(r'__init__\.py, line (\d+)', tb)
    if m:
        ln = int(m.group(1)); ctx = out.splitlines()
        a = max(1, ln-25); b = min(len(ctx), ln+25)
        print(f"\n--- Contexto {a}-{b} ---")
        for k in range(a, b+1):
            print(f"{k:5d}: {ctx[k-1]}")
    sys.exit(1)
