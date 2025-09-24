#!/usr/bin/env bash
set -euo pipefail
PYTHON=${PYTHON:-python}

routes="backend/routes.py"
[[ -f "$routes" ]] || { echo "ERROR: falta $routes"; exit 1; }
ts="$(date -u +%Y%m%d-%H%M%SZ)"
cp -f "$routes" "${routes}.${ts}.bak"
echo "[routes] Backup: ${routes}.${ts}.bak"

$PYTHON - <<'PY'
import io,re
p="backend/routes.py"
s=io.open(p,"r",encoding="utf-8").read()
orig=s

# Asegurar imports
if "from flask import" in s:
    if "request" not in s:
        s=s.replace("from flask import", "from flask import request,")
else:
    s = "from flask import Blueprint, request, jsonify\n"+s

# Insertar un manejador OPTIONS si no existe:
if "def _notes_options_" not in s:
    s += """
# == OPTIONS shim para /api/notes ==
try:
    from flask import current_app as _ca
    _bp = globals().get('bp')
except Exception:
    _bp = None

if _bp:
    @_bp.route("/api/notes", methods=["OPTIONS"])
    def _notes_options_():
        return ("", 204)
"""

# Asegurar que exista un endpoint que acepte POST (sin tocar tu lógica):
if 'methods=["GET","POST","OPTIONS"]' not in s and 'methods=[\'GET\',\'POST\',\'OPTIONS\']' not in s:
    s = re.sub(
        r'(@.*?/api/notes.*?methods=\[)([^\]]+)(\].*?\n)',
        lambda m: m.group(1) + "'GET','POST','OPTIONS'" + m.group(3) if "POST" not in m.group(2) else m.group(0),
        s, flags=re.S)

if s!=orig:
    io.open(p,"w",encoding="utf-8").write(s)
    print("[routes] métodos/OPTIONS asegurados")
else:
    print("[routes] Ya estaba OK")
PY

python -m py_compile backend/routes.py && echo "py_compile routes OK"
echo "Hecho. Recuerda hacer deploy."
