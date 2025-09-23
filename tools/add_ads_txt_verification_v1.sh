#!/usr/bin/env bash
set -euo pipefail
PUB="${1:?Uso: $0 ca-pub-XXXXXXXXXXXXXXX}"

ROUTES="backend/routes.py"
[[ -f "$ROUTES" ]] || { echo "ERROR: falta $ROUTES"; exit 1; }

python - <<PY
import io, re
p = "backend/routes.py"
s = io.open(p,"r",encoding="utf-8").read()
orig = s

if "from flask import Response" not in s:
    s = s.replace("from flask import", "from flask import Response, ")

if re.search(r"@app\.route\('/ads\.txt'", s) is None:
    block = (
        "\n\n@app.route('/ads.txt', methods=['GET','HEAD'])\n"
        "def ads_txt():\n"
        "    txt = 'google.com, {pub}, DIRECT, f08c47fec0942fa0\\n'\n"
        "    return Response(txt, mimetype='text/plain', headers={'Cache-Control':'public, max-age=3600'})\n"
    ).format(pub="${PUB}")
    s += block

if s != orig:
    io.open(p,"w",encoding="utf-8").write(s)
    print("[ads.txt] ruta agregada")
else:
    print("[ads.txt] ya existía")
PY

python -m py_compile backend/routes.py && echo "py_compile OK"
echo "Hecho. Despliega y luego prueba GET /ads.txt"
