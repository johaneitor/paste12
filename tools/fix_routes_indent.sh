#!/usr/bin/env bash
set -euo pipefail

FILE="backend/routes.py"
[[ -f "$FILE" ]] || { echo "No existe $FILE"; exit 1; }

cp -n "$FILE" "$FILE.bak.$(date -u +%Y%m%dT%H%M%SZ)" || true

python - "$FILE" <<'PY'
import sys, re
from pathlib import Path

p = Path(sys.argv[1])
src = p.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n").replace("\t","    ")
lines = src.splitlines()

def lead(s): return len(s)-len(s.lstrip(" "))
def seti(i,n): lines[i]=(" "*n)+lines[i].lstrip()

# 1) Imports y decoradores a columna 0
for i,ln in enumerate(lines):
    if re.match(r"^\s+from (flask|__future__)\s+import ", ln): lines[i]=ln.lstrip()
    if re.match(r"^\s+import (sqlalchemy|typing|datetime|re|json)\b", ln): lines[i]=ln.lstrip()
    if re.match(r"^\s+@api\.route\(", ln): lines[i]=ln.lstrip()
    if re.match(r"^\s+@api\.", ln): lines[i]=ln.lstrip()

# 2) Asegurar def top-level en col 0 si viene tras blanco o decorador
for i in range(1, len(lines)):
    if lines[i].lstrip().startswith("def ") and (lines[i-1].strip()=="" or lines[i-1].lstrip().startswith("@")):
        if lead(lines[i])>0: lines[i]=lines[i].lstrip()

# 3) Continuaciones: si la previa termina en '(' y la actual está menos indentada, darle +2
for i in range(1, len(lines)):
    if lines[i-1].rstrip().endswith("(") and lead(lines[i]) < lead(lines[i-1])+2:
        seti(i, lead(lines[i-1])+2)

# 4) Suavizar indent exagerado en líneas internas comunes
for i,ln in enumerate(lines):
    if re.match(r"^\s{9,}(text\s*=|query\s*=|return\b|if\b|for\b|with\b|data\s*=|items\s*=)", ln):
        seti(i, 4)  # dentro de una función

new = "\n".join(lines)
p.write_text(new, encoding="utf-8")
print("OK: routes.py normalizado")
PY

git add backend/routes.py >/dev/null 2>&1 || true
git commit -m "fix(api): normaliza indentación de backend/routes.py (tabs->spaces, decoradores/imports a col0)" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true

echo "→ Hecho. Cuando el deploy esté activo, probá:"
echo "  curl -sS -o /dev/null -w '%{http_code}\n' \"$1/__api_import_error\"  # 404 esperado"
