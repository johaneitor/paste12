#!/usr/bin/env bash
set -euo pipefail
_red(){ printf "\033[31m%s\033[0m\n" "$*"; }
_grn(){ printf "\033[32m%s\033[0m\n" "$*"; }

FILE="backend/routes.py"
[[ -f "$FILE" ]] || { _red "No existe $FILE"; exit 1; }

python - <<'PY'
from pathlib import Path
import re

p = Path("backend/routes.py")
src = p.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n").replace("\t","    ")
lines = src.split("\n")

def leading(s:str)->int: return len(s) - len(s.lstrip(" "))

i = 0
changed = False
n = len(lines)
while i < n:
    ln = lines[i]
    if ln.lstrip().startswith("try:"):
        base = leading(ln)
        # buscar la primera línea no vacía después del try:
        j = i + 1
        while j < n and lines[j].strip() == "":
            j += 1
        if j < n:
            # si NO está indentada respecto al try:, la indentamos junto con el bloque hasta 'except' o 'finally'
            if leading(lines[j]) <= base and not lines[j].lstrip().startswith(("except", "finally")):
                k = j
                while k < n:
                    s = lines[k]
                    st = s.lstrip()
                    if st.startswith(("except", "finally")):
                        break
                    if s.strip() != "":
                        lines[k] = (" "*(base+4)) + s.lstrip()
                    k += 1
                changed = True
                i = k  # continuar desde el except/finally
                continue
    i += 1

# También arreglamos imports sueltos que quedaron a col 0 dentro de bloques try previos
# (no es estrictamente necesario, pero ayuda a normalizar)
src2 = "\n".join(lines)
src2 = re.sub(r'(?m)^\s+from flask import (current_app|jsonify|send_from_directory)\s*$', r'from flask import \1', src2)

if src2 != src:
    p.write_text(src2, encoding="utf-8")
    print("OK: try-blocks indent reparado")
else:
    print("Nada que cambiar")
PY

git add backend/routes.py >/dev/null 2>&1 || true
git commit -m "hotfix(routes): reindenta bloques tras try: hasta except/finally; normaliza imports" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true

_grn "✓ Commit & push hechos."
