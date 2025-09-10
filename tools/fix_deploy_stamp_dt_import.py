#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ no existe wsgiapp/__init__.py"); sys.exit(2)

def R(): return W.read_text(encoding="utf-8")
def norm(s: str) -> str: return s.replace("\r\n","\n").replace("\r","\n").replace("\t","    ")

def gate():
    try:
        py_compile.compile(str(W), doraise=True)
        print("✓ py_compile OK"); return True
    except Exception as e:
        print("✗ py_compile FAIL:", e)
        tb = traceback.format_exc()
        m = re.search(r'__init__\.py, line (\d+)', tb)
        if m:
            ln = int(m.group(1)); ctx = R().splitlines()
            a = max(1, ln-35); b = min(len(ctx), ln+35)
            print(f"\n--- Ventana {a}-{b} ---")
            for k in range(a, b+1): print(f"{k:5d}: {ctx[k-1]}")
        return False

src = norm(R())
lines = src.split("\n")

# Localiza el if del handler de /api/deploy-stamp dentro de _app
m_if = re.search(r'(?m)^([ ]*)if\s+path\s*==\s*["\']/api/deploy-stamp["\']\s*and\s*method\s*in\s*\("GET","HEAD"\)\s*:\s*$', src)
if not m_if:
    print("✗ no encontré el bloque /api/deploy-stamp"); sys.exit(1)

if_ws = m_if.group(1)
if_base = len(if_ws)
if_idx = src[:m_if.start()].count("\n")

# Busca el 'try:' que abre el bloque
try_idx = None
i = if_idx + 1
while i < len(lines):
    L = lines[i]
    if L.strip() and (len(L) - len(L.lstrip(" "))) <= if_base:
        break  # dedent => fin del bloque
    if re.match(rf'^{re.escape(if_ws)}    try:\s*$', L):
        try_idx = i; break
    i += 1

if try_idx is None:
    print("✗ no encontré el try: dentro del handler"); sys.exit(1)

# Línea esperada de import local
imp_pat = re.compile(rf'^{re.escape(if_ws)}\s+import\s+os,\s*json(\s*,\s*datetime\s+as\s+_dt)?\s*(#.*)?$')

# ¿Existe ya el import? Si existe sin datetime, lo reemplazamos; si no, lo insertamos tras el try:
imp_line_idx = None
k = try_idx + 1
while k < len(lines):
    L = lines[k]
    if L.strip() and (len(L) - len(L.lstrip(" "))) <= if_base + 4:
        # seguimos dentro del try (indent == if_base+4)
        if re.match(rf'^{re.escape(if_ws)}\s+except\b', L):
            break
        if imp_pat.match(L):
            imp_line_idx = k
            break
    else:
        # si dedentea al nivel del if o menos, frenamos
        if (len(L) - len(L.lstrip(" "))) <= if_base:
            break
    k += 1

fixed = False
if imp_line_idx is not None:
    if "datetime as _dt" not in lines[imp_line_idx]:
        lines[imp_line_idx] = re.sub(r'json\s*(#.*)?$',
                                     r'json, datetime as _dt\1' if not re.search(r'#', lines[imp_line_idx]) else r'json, datetime as _dt',
                                     lines[imp_line_idx])
        fixed = True
else:
    # insertamos el import local inmediatamente después del try:
    lines.insert(try_idx + 1, if_ws + "        import os, json, datetime as _dt  # local, robusto")
    fixed = True

# Por si el código usa 'date = ... or ...' aseguremos el cómputo por ISO UTC si está vacío
# (idempotente: sólo añadimos el fallback si no está)
block_end = try_idx + 1
while block_end < len(lines):
    L = lines[block_end]
    if L.strip().startswith(if_ws + "    except") or (L.strip() and (len(L) - len(L.lstrip(" "))) <= if_base):
        break
    block_end += 1

has_fallback = any("isoformat()" in lines[t] and "Z" in lines[t] for t in range(try_idx, block_end))
if not has_fallback:
    # Buscar asignación de date; si no existe, la añadimos tras el import
    date_assigned = None
    for t in range(try_idx, block_end):
        if re.search(r'\bdate\s*=\s*', lines[t]):
            date_assigned = t; break
    insert_at = (date_assigned + 1) if date_assigned is not None else (try_idx + 2)
    lines.insert(insert_at, if_ws + '        if not date: date = _dt.datetime.utcnow().replace(microsecond=0).isoformat() + "Z"')
    fixed = True

out = "\n".join(lines)
if not fixed:
    print("OK: nada que cambiar (ya tenía datetime)"); 
    if not gate(): sys.exit(1)
    sys.exit(0)

bak = W.with_suffix(".py.fix_deploy_stamp_dt_import.bak")
if not bak.exists():
    shutil.copyfile(W, bak)
W.write_text(out, encoding="utf-8")
print(f"patched: import datetime/_dt arreglado en /api/deploy-stamp | backup={bak.name}")
if not gate(): sys.exit(1)
