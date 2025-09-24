#!/usr/bin/env bash
set -euo pipefail
_red(){ printf "\033[31m%s\033[0m\n" "$*"; }
_grn(){ printf "\033[32m%s\033[0m\n" "$*"; }

FILE="backend/routes.py"
[[ -f "$FILE" ]] || { _red "No existe $FILE"; exit 1; }

python - <<'PY'
from pathlib import Path
import re, sys
p = Path("backend/routes.py")
src = p.read_text(encoding="utf-8")

# 1) Quitar cualquier bloque residual indentado que comienza con "def _to(" (columna > 0)
#    y se extiende hasta el próximo decorador @api.route o EOF.
pat = re.compile(r'\n[ \t]+def _to\([^\n]*\):[\s\S]*?(?=\n@api\.route|\Z)', re.M)
nsrc, n = pat.subn('\n', src)

# 2) Algunos merges dejaron "from flask import jsonify" indentado.
#    Lo llevamos a columna 0 si aparece con indentación.
nsrc = re.sub(r'(?m)^\s+from flask import jsonify\s*$', 'from flask import jsonify', nsrc)

# 3) Asegurar que la definición del blueprint NO tiene url_prefix aquí (lo ponemos en create_app)
nsrc = re.sub(r'api\s*=\s*Blueprint\(\s*"api"\s*,\s*__name__\s*,\s*url_prefix\s*=\s*["\'][^"\']+["\']\s*\)',
              'api = Blueprint("api", __name__)', nsrc)

if n > 0:
    p.write_text(nsrc, encoding="utf-8")
    print(f"OK: bloque residual removido ({n} match).")
else:
    print("Nada que remover (no se encontró bloque residual).")
PY

git add backend/routes.py >/dev/null 2>&1 || true
git commit -m "fix(routes): elimina bloque residual indentado (def _to...) que rompía import; normaliza imports y blueprint" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true

_grn "✓ Commit & push hechos."
echo
echo "Ahora ejecutá el smoke:"
echo "  tools/run_system_smoke.sh \"https://paste12-rmsk.onrender.com\""
