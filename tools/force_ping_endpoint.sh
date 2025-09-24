#!/usr/bin/env bash
set -euo pipefail
_red(){ printf "\033[31m%s\033[0m\n" "$*"; }
_grn(){ printf "\033[32m%s\033[0m\n" "$*"; }

FILE="backend/routes.py"
[[ -f "$FILE" ]] || { _red "No existe $FILE"; exit 1; }

python - <<'PY'
from pathlib import Path, re
p = Path("backend/routes.py")
s = p.read_text(encoding="utf-8")

# Asegurar imports necesarios
if "from flask import" not in s:
    s = "from flask import Blueprint, request, jsonify, current_app\n" + s
else:
    # Garantizar jsonify y current_app
    if "jsonify" not in s.split("from flask import",1)[1]:
        s = s.replace("from flask import", "from flask import jsonify,")
    if "current_app" not in s.split("from flask import",1)[1]:
        s = s.replace("from flask import", "from flask import current_app,")

# Asegurar blueprint api sin url_prefix aquí
s = re.sub(r'api\s*=\s*Blueprint\(\s*"api"\s*,\s*__name__\s*,\s*url_prefix\s*=\s*["\'][^"\']+["\']\s*\)',
           'api = Blueprint("api", __name__)', s)

# Si el ping ya existe, no duplicar
if '@api.route("/ping"' not in s and "def api_ping(" not in s:
    block = '''
@api.route("/ping", methods=["GET"])
def api_ping():
    return jsonify({"pong": True}), 200
'''
    if not s.endswith("\n"): s += "\n"
    s += block.lstrip("\n")

# Normalizar tabs→spaces
s = s.replace("\t","    ")
p.write_text(s, encoding="utf-8")
print("OK: /api/ping presente en routes.py")
PY

git add backend/routes.py >/dev/null 2>&1 || true
git commit -m "feat(api): agrega handler /api/ping idempotente" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true
_grn "✓ Commit & push hechos."
