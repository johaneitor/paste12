#!/usr/bin/env bash
set -euo pipefail
F="backend/routes.py"
[[ -f "$F" ]] || { echo "No existe $F"; exit 1; }

# backup
cp -n "$F" "$F.bak.$(date -u +%Y%m%dT%H%M%SZ)" || true

python - "$F" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
src = p.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n").replace("\t","    ")

# 1) Normalizar el bloque def pick(...)
def_pat = re.compile(r'(?ms)^[ \t]*def[ \t]+pick\([^\)]*\):\n(?:[ \t].*\n)+')
if def_pat.search(src):
    new_pick = (
        "def pick(*vals):\n"
        "    for v in vals:\n"
        "        if v is None:\n"
        "            continue\n"
        "        s = str(v).strip()\n"
        "        if s != \"\":\n"
        "            return s\n"
        "    return \"\"\n\n"
    )
    src = def_pat.sub(new_pick, src, count=1)
else:
    # si no se encontró, lo insertamos arriba (raro, pero seguro)
    src = new_pick + src

# 2) Asegurar que la siguiente línea de uso quede a columna 0
#    Cualquier "   text = pick(" pasa a "text = pick("
src = re.sub(r'(?m)^[ \t]+text[ \t]*=[ \t]*pick\(', 'text = pick(', src)

p.write_text(src, encoding="utf-8")
print("OK: routes.py -> pick() reescrito y 'text = pick(' alineado.")
PY

git add backend/routes.py >/dev/null 2>&1 || true
git commit -m "fix(routes): normaliza indentación de pick() y alinea 'text = pick('" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true
echo "✓ Commit & push hecho."
