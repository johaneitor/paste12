#!/usr/bin/env bash
set -euo pipefail
TS="$(date -u +%Y%m%d-%H%M%SZ)"
ROUTES="backend/routes.py"

[[ -f "$ROUTES" ]] || { echo "ERROR: falta $ROUTES"; exit 2; }

cp -f "$ROUTES" "$ROUTES.$TS.bak"
echo "[backup] $ROUTES.$TS.bak"

python - <<'PY'
import io, re, sys
p="backend/routes.py"
s=io.open(p,"r",encoding="utf-8").read()
orig=s

# Reemplazar decoradores tipo @api_bp.options("/api/notes") por
# @api_bp.route("/api/notes", methods=["OPTIONS"])
pat = re.compile(r'@(\w+)\.options\(\s*([^)]*?)\s*\)')   # grupo1=nombre BP, grupo2=argumento(s)
s = pat.sub(r'@\1.route(\2, methods=["OPTIONS"])', s)

if s != orig:
    io.open(p,"w",encoding="utf-8").write(s)
    print("[routes] decoradores .options() reemplazados.")
else:
    print("[routes] no había decoradores .options().")

# Sanity: import api_bp
try:
    import importlib
    m = importlib.import_module("backend.routes")
    assert getattr(m, "api_bp", None) is not None
    print("[sanity] backend.routes.api_bp OK")
except Exception as e:
    import traceback; traceback.print_exc()
    sys.exit(1)
PY

echo "[done] routes parcheado"

# py_compile rápido
python - <<'PY'
import py_compile
py_compile.compile("backend/routes.py", doraise=True)
print("[py_compile] routes OK")
PY
