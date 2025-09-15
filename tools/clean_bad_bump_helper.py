#!/usr/bin/env python3
import re, sys, pathlib

W = pathlib.Path("wsgiapp/__init__.py")
src = W.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n")

orig = src

# 1) Eliminar cualquier definición previa (rota o no) de _bump_counter
src = re.sub(r'(?ms)^def[ \t]+_bump_counter\s*\([^)]*\):\s*\n(?:[ \t].*\n)*', '', src)

# 2) Eliminar líneas "aplastadas" típicas del helper malo (cur=...cur.execute... en una sola línea)
src = re.sub(r'(?m)^.*cur\s*=\s*db\.cursor\(\).*cur\.execute\(.*\n', '', src)

# 3) Normalizar dobles/triples saltos en exceso
src = re.sub(r'\n{3,}', '\n\n', src).rstrip() + '\n'

if src != orig:
    W.write_text(src, encoding="utf-8")
    print("OK: limpié definiciones rotas de _bump_counter y líneas aplastadas.")
else:
    print("OK: no encontré basura del helper; nada que limpiar.")
