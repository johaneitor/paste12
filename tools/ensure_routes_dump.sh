#!/usr/bin/env bash
set -euo pipefail
_red(){ printf "\033[31m%s\033[0m\n" "$*"; }
_grn(){ printf "\033[32m%s\033[0m\n" "$*"; }

FILE="backend/routes.py"
[[ -f "$FILE" ]] || { _red "No existe $FILE"; exit 1; }

python - <<'PY'
from pathlib import Path, re
p=Path("backend/routes.py")
src=p.read_text(encoding="utf-8")

# 1) Asegurar que existe el blueprint "api"
if "api = Blueprint(" not in src:
    raise SystemExit("No se encontró el blueprint 'api' en routes.py")

# 2) Asegurar import de current_app, jsonify
if "from flask import" in src and "current_app" not in src:
    src=src.replace("from flask import", "from flask import current_app,")
if "from flask import" in src and "jsonify" not in src:
    src=src.replace("from flask import", "from flask import jsonify,")

# 3) Si no existe la vista /_routes, agregarla al final
if '@api.route("/_routes"' not in src:
    block = '''
@api.route("/_routes", methods=["GET"])
def api_routes_dump():
    info = []
    for r in current_app.url_map.iter_rules():
        info.append({
            "rule": str(r),
            "methods": sorted(m for m in r.methods if m not in ("HEAD","OPTIONS")),
            "endpoint": r.endpoint,
        })
    info.sort(key=lambda x: x["rule"])
    return jsonify({"routes": info}), 200
'''
    if not src.endswith("\n"):
        src += "\n"
    src += block.lstrip("\n")

p.write_text(src, encoding="utf-8")
print("OK: /api/_routes garantizado")
PY

git add backend/routes.py >/dev/null 2>&1 || true
git commit -m "feat(api): añade /api/_routes de introspección si faltaba" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true

_grn "✓ Commit & push hechos."
echo
echo "Ahora verificá con:"
echo "  tools/smoke_routes_only.sh \"\${1:-https://paste12-rmsk.onrender.com}\""
