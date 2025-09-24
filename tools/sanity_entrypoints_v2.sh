#!/usr/bin/env bash
set -euo pipefail
echo "== Sanity WSGI/contract_shim =="

# 1) ¿wsgi exporta application?
python - <<'PY' || { echo "FAIL: wsgi.application"; exit 1; }
import importlib
m = importlib.import_module("wsgi")
assert hasattr(m, "application"), "wsgi.py no exporta 'application'"
print("✓ wsgi.application OK")
PY

# 2) ¿contract_shim.application sigue OK?
python - <<'PY' || { echo "FAIL: contract_shim.application"; exit 1; }
import importlib
m = importlib.import_module("contract_shim")
assert hasattr(m, "application"), "contract_shim.application ausente"
print("✓ contract_shim.application OK")
PY

# 3) Probar health sin tocar DB de forma agresiva
python - <<'PY' || { echo "FAIL: health minimal"; exit 1; }
import importlib, types
m = importlib.import_module("wsgi")
app = getattr(m, "application")
assert app, "no hay app"
print("✓ import wsgi OK (app presente)")
PY

echo "Listo."
