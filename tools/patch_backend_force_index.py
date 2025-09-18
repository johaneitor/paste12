#!/usr/bin/env python3
import re, pathlib, shutil, py_compile, sys

W = pathlib.Path("wsgiapp/__init__.py")
src = W.read_text(encoding="utf-8", errors="ignore")
bak = W.with_suffix(".force_index.bak")
if not bak.exists():
    shutil.copyfile(W, bak)

# Buscamos el bloque: if path in ("/", "/index.html") and method in ("GET","HEAD"):
pat = re.compile(r'(?m)^([ ]*)if[ ]+path[ ]+in[ ]*\(\s*"/",\s*"/index\.html"\s*\)[ ]+and[ ]+method[ ]+in[ ]*\(\s*"GET","HEAD"\s*\)\s*:\s*$')
lines = src.splitlines()
changed = 0
for i, line in enumerate(lines):
    m = pat.match(line)
    if m:
        ws = m.group(1)
        # Insertamos al final inmediato del bloque visible una asignación incondicional a _serve_index_html()
        # (si ya estaba, no duplicamos)
        j = i + 1
        need = True
        while j < len(lines) and (lines[j].startswith(ws + "    ") or lines[j].strip() == ""):
            if "_serve_index_html()" in lines[j]:
                need = False
            j += 1
        if need:
            lines.insert(i+1, ws + "    status, headers, body = _serve_index_html()")
            changed += 1
        break

if changed:
    W.write_text("\n".join(lines), encoding="utf-8")
    print(f"patched: fuerza index en '/' | backup={bak.name}")
else:
    print("OK: bloque '/' ya forzado o no encontrado (sin cambios).")

try:
    py_compile.compile(str(W), doraise=True)
    print("✓ py_compile OK")
except Exception as e:
    print("✗ py_compile FAIL:", e); sys.exit(1)
