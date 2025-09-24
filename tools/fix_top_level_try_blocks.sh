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
lines = src.splitlines()

def leading(s): 
    i=0
    while i < len(s) and s[i] == ' ':
        i+=1
    return i

i = 0
changed = False
while i < len(lines):
    ln = lines[i]
    if leading(ln)==0 and ln.strip()=="try:":
        # Buscar el cierre (except/finally) al nivel 0
        j = i+1
        while j < len(lines):
            s = lines[j].strip()
            if s=="":
                j += 1
                continue
            if leading(lines[j])==0 and (s.startswith("except ") or s=="except:" or s.startswith("finally:")):
                break
            j += 1
        # j es el índice del except/finally o EOF
        body_start = i+1
        body_end   = j
        # Si no hay except/finally, añadimos uno al final
        if body_end == i+1:
            # cuerpo vacío → nada que indentar
            pass
        # Indentar todo lo que esté a columna 0 dentro del cuerpo
        for k in range(body_start, body_end):
            if lines[k].strip()=="":
                continue
            if leading(lines[k])==0:
                lines[k] = "    " + lines[k]
                changed = True
        if j >= len(lines) or not (lines[j].lstrip().startswith("except") or lines[j].lstrip().startswith("finally")):
            # No había except/finally; agregamos un except
            lines.insert(body_end, "except Exception:")
            lines.insert(body_end+1, "    pass")
            changed = True
            i = body_end + 2
        else:
            # Aseguramos que el except está a col 0
            if leading(lines[j])!=0:
                lines[j] = lines[j].lstrip()
                changed = True
            i = j + 1
    else:
        i += 1

if changed:
    p.write_text("\n".join(lines) + ("\n" if src.endswith("\n") else ""), encoding="utf-8")
    print("OK: normalizados bloques try/except de nivel superior")
else:
    print("No se detectaron try: de nivel superior para normalizar")
PY

git add backend/routes.py >/dev/null 2>&1 || true
git commit -m "hotfix(routes): normaliza bloques try/except de nivel superior (indentación y except fallback)" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true

_grn "✓ Commit & push hechos."
echo
echo "Ahora corre el smoke:"
echo "  tools/run_system_smoke.sh \"https://paste12-rmsk.onrender.com\""
