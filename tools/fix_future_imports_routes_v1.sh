#!/usr/bin/env bash
set -euo pipefail

TARGET="backend/routes.py"
[[ -f "$TARGET" ]] || { echo "ERROR: falta $TARGET"; exit 3; }

TS="$(date -u +%Y%m%d-%H%M%SZ)"
BAK="backend/routes.$TS.bak"
cp -f "$TARGET" "$BAK"
echo "[routes-fix] Backup: $BAK"

python - <<'PY'
import io, re, sys, tokenize

p = "backend/routes.py"
s = io.open(p, "r", encoding="utf-8").read()

# 1) extraer y deduplicar líneas "from __future__ import ..."
future_lines = re.findall(r'^[ \t]*from[ \t]+__future__[ \t]+import[^\n]+$', s, flags=re.M)
if not future_lines:
    # Nada que mover; sólo compilar luego
    sys.exit(0)

# normalizar/ordenar/dedup
uniq = []
for line in future_lines:
    line = re.sub(r'^[ \t]+', '', line.rstrip())
    if line not in uniq:
        uniq.append(line)
future_block = "\n".join(uniq) + "\n"

# 2) quitar todas las ocurrencias actuales
s_wo_future = re.sub(r'^[ \t]*from[ \t]+__future__[ \t]+import[^\n]+\n?', '', s, flags=re.M)

# 3) hallar punto de inserción: después del docstring inicial (si lo hay),
#    o tras shebang/encoding y comentarios de cabecera.
lines = s_wo_future.splitlines(True)  # keepends
i = 0

# saltar BOM
if lines and lines[0].startswith("\ufeff"):
    lines[0] = lines[0].lstrip("\ufeff")

# saltar shebang y codificación
while i < len(lines) and (lines[i].startswith("#!") or re.match(r'^[ \t]*#.*coding[:=]', lines[i])):
    i += 1

# saltar comentarios y blancos
while i < len(lines) and (re.match(r'^[ \t]*#', lines[i]) or lines[i].strip() == ""):
    i += 1

# si hay docstring triple al inicio, avanzar hasta su cierre
def is_triple_quote_start(l):
    l = l.lstrip()
    return l.startswith('"""') or l.startswith("'''")

if i < len(lines) and is_triple_quote_start(lines[i]):
    q = '"""' if lines[i].lstrip().startswith('"""') else "'''"
    # avanzar hasta cierre
    j = i
    started = False
    while j < len(lines):
        if j == i:
            # primera línea (puede abrir y cerrar en la misma)
            if lines[j].count(q) >= 2:
                j += 1
                started = True
                break
            else:
                j += 1
                started = True
        else:
            if q in lines[j]:
                j += 1
                break
            j += 1
    i = j

# insertar el bloque future si no está ya exactamente ahí
new_s = "".join(lines[:i]) + future_block + "".join(lines[i:])

io.open(p, "w", encoding="utf-8").write(new_s)
PY

# 4) compilar
python -m py_compile backend/routes.py && echo "[routes-fix] py_compile OK" || { echo "[routes-fix] py_compile FAIL"; exit 4; }
echo "[routes-fix] Hecho."
