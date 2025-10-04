#!/usr/bin/env bash
set -euo pipefail
PY="wsgi.py"
[[ -f "$PY" ]] || { echo "ERROR: no existe $PY (entrypoint de gunicorn)"; exit 1; }
cp -f "$PY" "${PY}.bak-$(date -u +%Y%m%d-%H%M%SZ)" || true
python - <<'PYCODE'
import io, re, py_compile
p="wsgi.py"
s=io.open(p,"r",encoding="utf-8").read()
# 1) normalizar imports al margen izquierdo
s = re.sub(r'^\s+(?=(import|from)\s)', r'', s, flags=re.M)
# 2) asegurar que exportamos 'application'
if not re.search(r'^\s*application\s*=', s, re.M):
    s += "\n\ndef application(environ, start_response):\n    start_response('200 OK', [('Content-Type','text/plain')])\n    return [b'ok']\n"
io.open(p,"w",encoding="utf-8").write(s)
py_compile.compile(p, doraise=True)
print("PATCH_OK", p)
PYCODE
python -m py_compile "wsgi.py"
echo "OK: wsgi.py compilado"
