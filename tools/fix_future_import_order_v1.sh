#!/usr/bin/env bash
set -euo pipefail

P="backend/__init__.py"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
[[ -f "$P" ]] || { echo "ERROR: falta $P"; exit 1; }
cp -f "$P" "$P.$TS.bak"
echo "[future-fix] Backup: $P.$TS.bak"

python - <<'PY'
import io, re, sys, pathlib
p = pathlib.Path("backend/__init__.py")
s = p.read_text(encoding="utf-8")

orig = s

# 1) Extraer todas las líneas "from __future__ import ..."
future_rx = re.compile(r'^\s*from\s+__future__\s+import\s+[^\n]+$', re.M)
futures = [m.group(0) for m in future_rx.finditer(s)]
# Unificar y mantener orden de aparición
seen = set()
futures_unique = []
for line in futures:
    if line not in seen:
        futures_unique.append(line)
        seen.add(line)

# 2) Quitar todas las ocurrencias del archivo
s = future_rx.sub('', s)

# 3) Determinar índice de inserción:
#   - tras shebang/encoding/comments vacíos y docstring inicial si existe
lines = s.splitlines(True)

i = 0
# saltar shebang y codificación y líneas en blanco/comentarios iniciales
while i < len(lines):
    L = lines[i]
    if i == 0 and L.startswith("#!"):
        i += 1
        continue
    # pep263 encoding
    if re.match(r'^\s*#.*coding[:=]\s*[-\w.]+', L):
        i += 1
        continue
    if re.match(r'^\s*#', L) or re.match(r'^\s*$', L):
        i += 1
        continue
    break

# docstring de módulo triple-quote
def _docstring_span(start):
    if start >= len(lines): return None
    L = lines[start].lstrip()
    if L.startswith('"""') or L.startswith("'''"):
        q = L[:3]
        # Si cierra en la misma línea
        if L.count(q) >= 2:
            return (start, start)
        j = start + 1
        while j < len(lines):
            if q in lines[j]:
                return (start, j)
            j += 1
    return None

ds = _docstring_span(i)
if ds:
    i = ds[1] + 1
    # saltar líneas en blanco posteriores inmediatas
    while i < len(lines) and re.match(r'^\s*$', lines[i]):
        i += 1

# 4) Insertar los futures (si hay)
if futures_unique:
    block = "".join(l if l.endswith("\n") else l + "\n" for l in futures_unique)
    # Si ya están exactamente ahí, evitar duplicar
    before = "".join(lines[:i])
    after  = "".join(lines[i:])
    candidate = before + block + after
    s_new = candidate
else:
    s_new = "".join(lines)

if s_new != orig:
    p.write_text(s_new, encoding="utf-8")
    print("[future-fix] Reordenado __future__ OK")
else:
    print("[future-fix] No hubo cambios (ya estaba OK)")
PY

python -m py_compile backend/__init__.py && echo "[future-fix] py_compile OK" || { echo "py_compile FAIL"; exit 2; }
echo "Listo. Ahora puedes redeployar."
