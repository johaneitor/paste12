#!/usr/bin/env bash
set -euo pipefail
echo "== Sanity WSGI/contract_shim =="

fail=0
# Debe exportar 'application'
grep -qE 'application\s*=' wsgi.py || { echo "FAIL: wsgi.py no exporta 'application'"; fail=1; }
grep -qE 'application\s*=' contract_shim.py || { echo "FAIL: contract_shim.py no exporta 'application'"; fail=1; }

# CORS debe estar importado si se usa
if grep -q 'CORS(' backend/__init__.py 2>/dev/null; then
  grep -q 'from flask_cors import CORS' backend/__init__.py || { echo "FAIL: falta 'from flask_cors import CORS' en backend/__init__.py"; fail=1; }
fi

# Comprobación rápida de imports que suelen causar circularidad:
if grep -qE 'from\s+backend\s+import\s+db' backend/routes.py 2>/dev/null; then
  echo "OK: routes importa db del paquete backend (esperado)"
fi

python - <<'PY'
import importlib, sys
for mod in ("contract_shim", "wsgi"):
    try:
        m = importlib.import_module(mod)
        app = getattr(m, "application", None)
        assert callable(getattr(app, "__call__", None)), f"{mod}.application no es WSGI callable"
        print(f"✓ {mod}.application OK")
    except Exception as e:
        print(f"FAIL: importar {mod} -> {e}")
        sys.exit(1)
print("✓ Entrypoints WSGI OK")
PY

[[ $fail -eq 0 ]] || { echo "Corrige los FAIL anteriores y reintenta."; exit 2; }
