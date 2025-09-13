#!/usr/bin/env python3
import re, sys, pathlib
p = pathlib.Path("wsgiapp/__init__.py")
s = p.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n").replace("\r","\n").replace("\t","    ")
bad = []
for m in re.finditer(r'(?m)^([ ]*)def[ ]+([A-Za-z_][A-Za-z0-9_]*)\s*\([^)]*\)\s*:\s*\n(?!\1[ ]+)', s):
    bad.append((m.start(), m.group(2)))
if bad:
    print("Funciones sin cuerpo (o indent roto) detectadas:")
    for pos, name in bad:
        print(f" - {name} @pos {pos}")
    sys.exit(1)
print("OK: no hay defs vacías")
