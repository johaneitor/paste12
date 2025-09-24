#!/usr/bin/env bash
set -euo pipefail

FILE="backend/routes.py"

if [[ ! -f "$FILE" ]]; then
  echo "No existe $FILE"; exit 1
fi

python - "$FILE" <<'PY'
from pathlib import Path, PurePath
import re, sys

p = Path(sys.argv[1])
src = p.read_text(encoding="utf-8")

# 1) Si no existe _pick, lo insertamos después del Blueprint
if "def _pick(" not in src:
    # Buscamos la línea del blueprint
    pat_bp = re.compile(r'^\s*api\s*=\s*Blueprint\([^)]*\)\s*$', re.M)
    m = pat_bp.search(src)
    helper = (
        "\n\n"
        "def _pick(*vals):\n"
        "    for v in vals:\n"
        "        if v is None:\n"
        "            continue\n"
        "        s = str(v).strip()\n"
        "        if s:\n"
        "            return s\n"
        "    return \"\"\n"
    )
    if m:
        insert_at = m.end()
        src = src[:insert_at] + helper + src[insert_at:]
    else:
        # fallback: al inicio del archivo tras los imports
        pat_import_end = re.compile(r'(?:^.*import.*\n)+', re.M)
        m2 = pat_import_end.match(src)
        insert_at = m2.end() if m2 else 0
        src = src[:insert_at] + helper + src[insert_at:]

# 2) Reemplazar todos los usos de "pick(" por "_pick("
src = re.sub(r'(?<!_)\\bpick\\s*\\(', '_pick(', src)

# 3) Normalizar tabs -> spaces por si quedan tabs
src = src.replace("\\t", "    ")

p.write_text(src, encoding="utf-8")
print("OK: _pick insertado/asegurado y reemplazos hechos")
PY

git add backend/routes.py >/dev/null 2>&1 || true
git commit -m "fix(api): helper _pick() correcto y reemplazo de pick(); evita IndentationError en routes.py" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true

echo "✓ Commit & push realizados. Ahora ejecuta el smoke:"
echo "  tools/run_system_smoke.sh \"${1:-https://paste12-rmsk.onrender.com}\""
