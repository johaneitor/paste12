#!/usr/bin/env bash
set -euo pipefail

TARGET="backend/routes.py"
[[ -f "$TARGET" ]] || { echo "ERROR: no existe $TARGET"; exit 1; }

python - <<'PY'
import io, re, sys
p = "backend/routes.py"
s = io.open(p, "r", encoding="utf-8").read()
orig = s

# Ya existe un HEAD para /api/notes?
if re.search(r"@app\.route\(\s*['\"]/api/notes['\"].*methods=\[.*'HEAD'.*\]\)", s, re.S):
    print("INFO: HEAD /api/notes ya existe, no hago nada.")
else:
    # Intentar detectar importaciones de Flask
    if not re.search(r"\bfrom flask import\b", s):
        s = "from flask import make_response\n" + s
    elif not re.search(r"\bmake_response\b", s):
        s = re.sub(r"(from flask import [^\n]+)", r"\1, make_response", s)

    block = r"""
@app.route('/api/notes', methods=['HEAD'])
def api_notes_head():
    # Respuesta vacía para HEAD con CORS estándar
    resp = make_response('', 200)
    resp.headers['Access-Control-Allow-Origin'] = '*'
    resp.headers['Access-Control-Allow-Methods'] = 'GET, POST, HEAD, OPTIONS'
    resp.headers['Access-Control-Allow-Headers'] = 'Content-Type'
    resp.headers['Access-Control-Max-Age'] = '86400'
    # Opcional: tipo json para clientes que lo esperan aunque no haya body
    resp.headers['Content-Type'] = 'application/json'
    return resp
"""
    # Inserta al final del archivo
    if not s.endswith("\n"):
        s += "\n"
    s += block

if s != orig:
    io.open(p, "w", encoding="utf-8").write(s)
    print("OK: agregado handler HEAD /api/notes")
else:
    print("OK: sin cambios")
PY

python -m py_compile backend/routes.py && echo "py_compile routes OK"
