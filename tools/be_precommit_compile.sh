#!/usr/bin/env bash
set -euo pipefail
python - <<'PY'
import py_compile, sys
py_compile.compile('wsgiapp/__init__.py', doraise=True)
print("OK: wsgiapp/__init__.py compilado")
PY
