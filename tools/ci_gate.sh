#!/usr/bin/env bash
set -euo pipefail
python - <<'PY'
import py_compile, importlib
py_compile.compile("wsgiapp/__init__.py", doraise=True)
print("✓ py_compile OK")
m = importlib.import_module("wsgiapp")
assert callable(getattr(m,"app",None)), "wsgiapp:app no callable"
print("✓ import wsgiapp:app OK")
PY
python tools/assert_wsgi_structure_v2.py
BASE="${1:-}"
[ -n "$BASE" ] && python tools/assert_contracts_min.py "$BASE" || true
