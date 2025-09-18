#!/usr/bin/env python3
import re, pathlib, subprocess
W = pathlib.Path("wsgiapp/__init__.py")
s = W.read_text(encoding="utf-8", errors="ignore")

# Inserta un campo "rev" en la respuesta de /api/health si no está
if '"rev"' in s or "'rev'" in s:
    print("OK: health ya expone rev"); exit(0)

rev = subprocess.check_output(["git","rev-parse","--short=12","HEAD"], text=True).strip()
pat = re.compile(r'(/api/health.*?\n)(\s*return\s+_json\(\s*\{[^\}]*"ok"\s*:\s*True[^\}]*\}\s*\).*)', re.S)
m = pat.search(s)
if not m:
    print("X: no pude localizar /api/health para parchear (no bloquea)"); exit(0)

head, ret = m.groups()
new_ret = ret.replace("{", "{ 'rev': '"+rev+"', ", 1).replace('"ok"', "'ok'")
s = s.replace(ret, new_ret)
W.write_text(s, encoding="utf-8")
print("OK: agregado 'rev' a /api/health =", rev)
