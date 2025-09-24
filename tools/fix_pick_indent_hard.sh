#!/usr/bin/env bash
set -euo pipefail

FILE="backend/routes.py"
BASE="${1:-https://paste12-rmsk.onrender.com}"

if [[ ! -f "$FILE" ]]; then
  echo "No existe $FILE"; exit 1
fi

python - <<'PY'
from pathlib import Path, re
p = Path("backend/routes.py")
src = p.read_text(encoding="utf-8")

# 0) Normalizar saltos y tabs -> espacios
src = src.replace("\r\n","\n").replace("\r","\n").replace("\t","    ")

# 1) Asegurar helper _pick() canónico (y borrar variantes rotas)
#    Eliminamos cualquier def pick/__pick/_pick previo y reinsertamos uno correcto
src_lines = src.splitlines()
out = []
skip = False
for i, ln in enumerate(src_lines):
    if ln.lstrip().startswith("def pick(") or ln.lstrip().startswith("def __pick(") or ln.lstrip().startswith("def _pick("):
        skip = True
    if skip and ln.strip().endswith("return \"\""):
        # saltar también esta línea y dejar de saltar a partir de la siguiente
        skip = False
        continue
    if not skip:
        out.append(ln)

src = "\n".join(out)

# Insertar helper _pick() después de la creación del blueprint o al inicio
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
inserted = False
for marker in ("api = Blueprint", "api=Blueprint", "Blueprint(\"api\"", "Blueprint('api'"):
    if marker in src:
        pos = src.index(marker)
        nl = src.find("\n", pos)
        if nl == -1: nl = len(src)
        src = src[:nl] + helper + src[nl:]
        inserted = True
        break
if not inserted:
    src = helper + "\n" + src

# 2) Reemplazar llamadas a pick/__pick por _pick
src = src.replace("pick(", "_pick(").replace("__pick(", "_pick(")

# 3) Guardar
Path("backend/routes.py").write_text(src, encoding="utf-8")
print("OK: routes.py normalizado: helper _pick() + llamadas actualizadas + tabs→espacios")
PY

git add backend/routes.py >/dev/null 2>&1 || true
git commit -m "fix(api): helper _pick() canónico; reemplazo pick/__pick→_pick; normaliza indent (tabs→espacios)" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true

# Ping rápido al import checker
code="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/__api_import_error" || true)"
echo "__api_import_error status: $code (404 esperado tras redeploy)"
echo "Si aún no es 404, dale unos segundos y reintenta:"
echo "  tools/run_system_smoke.sh \"$BASE\""
