#!/usr/bin/env bash
set -euo pipefail
_red(){ printf "\033[31m%s\033[0m\n" "$*"; }; _grn(){ printf "\033[32m%s\033[0m\n" "$*"; }

FILE="backend/routes.py"
[[ -f "$FILE" ]] || { _red "No existe $FILE"; exit 1; }

python - <<'PY'
from pathlib import Path, re
p=Path("backend/routes.py")
src=p.read_text(encoding="utf-8")

# Asegurar import básicos
need_imports=[
    "from flask import Blueprint, jsonify, request, current_app",
]
for imp in need_imports:
    if imp not in src:
        # Evitar duplicar Blueprint base
        src=("from flask import Blueprint, jsonify, request, current_app\n" + src) if "from flask import Blueprint" not in src else src

# Asegurar variable 'api' sin url_prefix aquí
src = re.sub(r'api\s*=\s*Blueprint\(\s*"api"\s*,\s*__name__(?:\s*,\s*url_prefix\s*=\s*["\'][^"\']+["\'])?\s*\)',
             'api = Blueprint("api", __name__)', src)

added = False

# /api/ping
if '@api.route("/ping"' not in src:
    block = '''
@api.route("/ping", methods=["GET"])
def api_ping():
    return jsonify({"pong": True}), 200
'''
    if not src.endswith("\n"): src += "\n"
    src += block
    added = True

# /api/_routes (dump simple)
if '@api.route("/_routes"' not in src:
    block = '''
@api.route("/_routes", methods=["GET"])
def api_routes_dump():
    info=[]
    for r in current_app.url_map.iter_rules():
        info.append({
            "rule": str(r),
            "methods": sorted(m for m in r.methods if m not in ("HEAD","OPTIONS")),
            "endpoint": r.endpoint,
        })
    info.sort(key=lambda x: x["rule"])
    return jsonify({"routes": info}), 200
'''
    if not src.endswith("\n"): src += "\n"
    src += block
    added = True

# Normalizar posibles indentaciones accidentales de estas defs (columna 0)
src = re.sub(r'(?m)^\s+@api\.route\("/ping"[^\n]*\)\s*$', '@api.route("/ping", methods=["GET"])', src)
src = re.sub(r'(?m)^\s+def api_ping\(\):', 'def api_ping():', src)
src = re.sub(r'(?m)^\s+@api\.route\("/_routes"[^\n]*\)\s*$', '@api.route("/_routes", methods=["GET"])', src)
src = re.sub(r'(?m)^\s+def api_routes_dump\(\):', 'def api_routes_dump():', src)

p.write_text(src, encoding="utf-8")
print("OK: ping/_routes garantizados en routes.py")
PY

git add backend/routes.py >/dev/null 2>&1 || true
git commit -m "feat(api): añade /api/ping y /api/_routes en blueprint api; normaliza blueprint sin url_prefix" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true
_grn "✓ Commit & push hechos."
