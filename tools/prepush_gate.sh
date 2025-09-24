#!/usr/bin/env bash
set -euo pipefail
echo "== prepush gate =="
python - <<'PY'
import py_compile
py_compile.compile("wsgiapp/__init__.py", doraise=True)
print("✓ py_compile OK")
PY
echo "Sugerido: correr también tests locales contra staging (opcional)."
