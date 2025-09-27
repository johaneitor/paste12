#!/usr/bin/env bash
set -euo pipefail
TS="$(date -u +%Y%m%d-%H%M%SZ)"
R="backend/routes.py"
[[ -f "$R" ]] || { echo "ERROR: falta $R"; exit 1; }
cp -f "$R" "$R.$TS.bak"
echo "[routes] Backup: $R.$TS.bak"

python - <<'PY'
import io, re, textwrap
p = "backend/routes.py"
s = io.open(p, "r", encoding="utf-8").read()

def ensure_imports(s:str)->str:
    # asegurar imports base
    if "from flask import" not in s:
        s = 'from flask import Blueprint, jsonify, request\n' + s
    else:
        if "Blueprint" not in s:
            s = s.replace("from flask import", "from flask import Blueprint,")
        if "request" not in s:
            s = s.replace("from flask import", "from flask import request,")
        if "jsonify" not in s:
            s = s.replace("from flask import", "from flask import jsonify,")
    return s

def ensure_api_bp(s:str)->str:
    if re.search(r'\bapi_bp\s*=\s*Blueprint\(', s) is None:
        s = 'api_bp = Blueprint("api", __name__)\n' + s
    return s

def patch_options(s:str)->str:
    # Sustituir decoradores inexistentes @api_bp.options(...) por route(..., methods=["OPTIONS"])
    s = re.sub(r'@api_bp\.options\(\s*([^)]+)\)',
               r'@api_bp.route(\1, methods=["OPTIONS"])', s)
    return s

def ensure_notes_options(s:str)->str:
    # Crear handler OPTIONS /api/notes si no existe
    if not re.search(r'@api_bp\.route\(\s*[\'"]\/api\/notes[\'"]\s*,\s*methods=\[["\']OPTIONS["\']\]\s*\)', s):
        block = '''
@api_bp.route("/api/notes", methods=["OPTIONS"])
def _notes_preflight():
    resp = jsonify(ok=True)
    resp.status_code = 204
    resp.headers["Access-Control-Allow-Origin"]  = "*"
    resp.headers["Access-Control-Allow-Methods"] = "GET, POST, HEAD, OPTIONS"
    resp.headers["Access-Control-Allow-Headers"] = "Content-Type"
    resp.headers["Access-Control-Max-Age"]       = "86400"
    return resp
'''
        s += textwrap.dedent(block)
    return s

def ensure_api_health(s:str)->str:
    if not re.search(r'@api_bp\.(get|route)\(\s*[\'"]\/api\/health', s):
        block = '''
@api_bp.get("/api/health")
def api_health():
    return jsonify(ok=True, api=True, ver="routes-v3")
'''
        s += textwrap.dedent(block)
    return s

s = ensure_imports(s)
s = ensure_api_bp(s)
s = patch_options(s)
s = ensure_notes_options(s)
s = ensure_api_health(s)

io.open(p, "w", encoding="utf-8").write(s)
print("[routes] parche aplicado")
PY

# Verificación de sintaxis (best-effort)
python -m py_compile backend/routes.py && echo "[routes] py_compile OK" || true
