#!/usr/bin/env bash
set -euo pipefail
R="backend/routes.py"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
[[ -f "$R" ]] || { echo "ERROR: falta $R"; exit 2; }
cp -f "$R" "$R.$TS.bak"; echo "[backup] $R.$TS.bak"

python - <<'PY'
import io, re, sys

p="backend/routes.py"
s=io.open(p,"r",encoding="utf-8").read()
orig=s

# 1) Asegurar imports y blueprint
if "Blueprint(" not in s or "api_bp =" not in s:
    pre='from flask import Blueprint, request, jsonify, current_app\n'
    bp='api_bp = Blueprint("api", __name__)\n'
    if "from flask import" not in s:
        s=pre+bp+s
    else:
        # insertar el blueprint tras la primera línea de imports
        s=re.sub(r'(from flask[^\n]*\n)', r'\1'+bp, s, count=1)

# 2) Reemplazar decoradores inexistentes @api_bp.options(...) por route(..., methods=['OPTIONS'])
s=re.sub(r'@api_bp\.options\(\s*([\'\"][^\'\"]+[\'\"])s*\)',
         r'@api_bp.route(\1, methods=[\'OPTIONS\'])', s)

# 3) Asegurar handler explícito OPTIONS si no quedó ninguno
if not re.search(r'@api_bp\.route\(\s*[\'\"]/api/notes[\'\"].*methods=.*OPTIONS', s, re.S|re.I):
    s += """

@api_bp.route("/api/notes", methods=["OPTIONS"])
def _notes_options():
    # 204 vacio, CORS lo completa en after_request
    return ("", 204)
"""

# 4) Evitar fallos por return None en OPTIONS
s=re.sub(r'(def\s+[^\(]+\([^\)]*\):\s*\n)(\s*pass\s*\n)', r'\1    return ("", 204)\n', s)

if s!=orig:
    io.open(p,"w",encoding="utf-8").write(s)
    print("[routes] normalizado: decorators + OPTIONS")
else:
    print("[routes] ya estaba OK")
PY

# 5) py_compile rápido
python - <<'PY'
import py_compile; py_compile.compile("backend/routes.py", doraise=True)
print("py_compile routes OK")
PY
echo "Listo."
