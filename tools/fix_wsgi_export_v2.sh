#!/usr/bin/env bash
# Uso: tools/fix_wsgi_export_v2.sh
set -euo pipefail
[[ -f wsgi.py ]] || { echo "ERROR: falta wsgi.py"; exit 2; }

TS="$(date -u +%Y%m%d-%H%M%SZ)"
cp -f wsgi.py "wsgi.$TS.bak"

python - <<'PY'
import io, re, sys
p="wsgi.py"
s=io.open(p,"r",encoding="utf-8").read()
orig=s
# asegurar from backend import create_app, db opcional, etc. pero sin romper
if not re.search(r'\bapplication\s*=', s):
    if "create_app(" in s:
        pass
    else:
        # crear fábrica mínima si no existe
        s = 'from backend import create_app\napplication = create_app()\n' + s
# fallback directo si hay app
if not re.search(r'\bapplication\s*=', s):
    s = re.sub(r'\bapp\s*=\s*create_app\(\)', 'application = create_app()', s)

if s!=orig:
    io.open(p,"w",encoding="utf-8").write(s)
    print("wsgi.py actualizado")
else:
    print("INFO: wsgi.py ya exporta application (o fábrica detectada)")
PY

python -m py_compile wsgi.py && echo "py_compile OK"
echo "Listo."
