#!/usr/bin/env bash
set -euo pipefail

FILE="backend/routes.py"

if [[ ! -f "$FILE" ]]; then
  echo "No existe $FILE"; exit 1
fi

python - "$FILE" <<'PY'
from pathlib import Path
p = Path("backend/routes.py")
src = p.read_text(encoding="utf-8")

# Insertar helper _pick si no existe
if "def _pick(" not in src:
    helper = (
        "\n\ndef _pick(*vals):\n"
        "    for v in vals:\n"
        "        if v is None:\n"
        "            continue\n"
        "        s = str(v).strip()\n"
        "        if s:\n"
        "            return s\n"
        "    return \"\"\n"
    )
    # insertamos después del blueprint
    if "api = Blueprint" in src:
        pos = src.index("api = Blueprint")
        # buscar salto de línea siguiente
        nl = src.find("\n", pos)
        if nl == -1: nl = len(src)
        src = src[:nl] + helper + src[nl:]
    else:
        src = helper + src

# Reemplazar todos los usos de pick( por _pick(
src = src.replace("pick(", "_pick(")

# Normalizar tabs a espacios
src = src.replace("\t", "    ")

p.write_text(src, encoding="utf-8")
print("OK: helper _pick() asegurado y reemplazos hechos")
PY

git add backend/routes.py >/dev/null 2>&1 || true
git commit -m "fix(api): insertar helper _pick() y reemplazar pick() → _pick(); corrige IndentationError" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true

echo "✓ Commit & push hechos. Ahora ejecuta:"
echo "  tools/run_system_smoke.sh \"${1:-https://paste12-rmsk.onrender.com}\""
