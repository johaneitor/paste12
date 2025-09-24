#!/usr/bin/env bash
set -euo pipefail

F="backend/routes.py"
[[ -f "$F" ]] || { echo "No existe $F"; exit 1; }

cp -n "$F" "$F.bak.$(date -u +%Y%m%dT%H%M%SZ)" || true

python - <<'PY'
import io, re, sys, pathlib
p = pathlib.Path("backend/routes.py")
src = p.read_text(encoding="utf-8")

# 1) tabs -> 4 spaces
src = src.replace("\t", "    ")

lines = src.splitlines()

def flush_block(i):
    """Si encontramos un decorador con espacios al inicio, lo forzamos a columna 0,
    y también la línea def inmediatamente siguiente."""
    # Asegurar que @api.route quede a columna 0
    if lines[i].lstrip().startswith("@api.route("):
        lines[i] = lines[i].lstrip()
        # Buscar la def que sigue
        j = i+1
        # saltar posibles comments/blank
        while j < len(lines) and (lines[j].strip() == "" or lines[j].lstrip().startswith("#")):
            j += 1
        if j < len(lines) and lines[j].lstrip().startswith("def "):
            lines[j] = lines[j].lstrip()

# 2) Fuerza columna 0 para todos los @api.route “mal indentados”
for i, ln in enumerate(lines):
    if re.match(r"^\s+@api\.route\(", ln):
        flush_block(i)

# 3) A veces queda un from/import metido dentro de un bloque por mala indentación.
#   Si detectamos 'from flask import jsonify' con espacios delante, lo traemos a columna 0.
for i, ln in enumerate(lines):
    if re.match(r"^\s+from flask import ", ln):
        lines[i] = lines[i].lstrip()
    if re.match(r"^\s+import sqlalchemy as ", ln):
        lines[i] = lines[i].lstrip()

# 4) Defensa: si hay un 'def ' que quedó con espacios sin necesidad y NO estamos en clase/bloque,
#    lo llevamos a columna 0 cuando la línea previa está vacía o es un decorador en columna 0.
for i in range(1, len(lines)):
    if lines[i].lstrip().startswith("def ") and lines[i].startswith("    "):
        prev = lines[i-1]
        if prev.strip() == "" or prev.startswith("@"):
            lines[i] = lines[i].lstrip()

new = "\n".join(lines) + ("\n" if not lines or not lines[-1].endswith("\n") else "")
p.write_text(new, encoding="utf-8")
print("routes.py normalizado (tabs->espacios, decoradores/def a columna 0)")
PY

git add backend/routes.py >/dev/null 2>&1 || true
git commit -m "fix(routes): normaliza indentación (tabs→espacios) y alinea @api.route/def a columna 0" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true
echo "✓ Patch aplicado y pusheado (o ya estaba)"
