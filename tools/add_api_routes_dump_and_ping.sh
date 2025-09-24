#!/usr/bin/env bash
set -euo pipefail
_red(){ printf "\033[31m%s\033[0m\n" "$*"; }
_grn(){ printf "\033[32m%s\033[0m\n" "$*"; }

FILE="backend/routes.py"
[[ -f "$FILE" ]] || { _red "No existe $FILE"; exit 1; }

python - <<'PY'
from pathlib import Path
p = Path("backend/routes.py")
s = p.read_text(encoding="utf-8")

def ensure_import(line: str):
    global s
    if line not in s:
        # Inserta lo más arriba posible tras primera línea de imports/encoding
        p1 = s.find("\n")
        if p1 == -1: p1 = 0
        s = s[:p1+1] + line + "\n" + s[p1+1:]

# Asegurar imports mínimos
if "from flask import" not in s:
    s = "from flask import Blueprint, request, jsonify, current_app\n" + s
else:
    # Garantizar jsonify y current_app presentes
    if "jsonify" not in s:
        s = s.replace("from flask import", "from flask import jsonify,")
    if "current_app" not in s:
        s = s.replace("from flask import", "from flask import current_app,")

# Asegurar definición de blueprint sin url_prefix aquí
import re
s = re.sub(r'api\s*=\s*Blueprint\(\s*"api"\s*,\s*__name__\s*,\s*url_prefix\s*=\s*["\'][^"\']+["\']\s*\)',
           'api = Blueprint("api", __name__)', s)

blocks = []

if '@api.route("/ping"' not in s and "def api_ping(" not in s:
    blocks.append('''
@api.route("/ping", methods=["GET"])
def api_ping():
    return jsonify({"pong": True}), 200
''')

if '@api.route("/_routes"' not in s and "def api_routes_dump(" not in s:
    blocks.append('''
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
''')

if '@api.route("/routes"' not in s and "def api_routes_dump_alias(" not in s:
    blocks.append('''
@api.route("/routes", methods=["GET"])
def api_routes_dump_alias():
    return api_routes_dump()
''')

if blocks:
    if not s.endswith("\n"): s += "\n"
    s += "\n".join(b.lstrip("\n") for b in blocks)

# Normalizar tabs → 4 espacios (defensivo)
s = s.replace("\t", "    ")

p.write_text(s, encoding="utf-8")
print("OK: ping/_routes/routes añadidos o verificados")
PY

git add backend/routes.py >/dev/null 2>&1 || true
git commit -m "feat(api): asegura /api/ping y /api/_routes (/api/routes alias) en routes.py" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true

_grn "✓ Commit & push hechos."
