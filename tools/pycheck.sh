#!/usr/bin/env bash
set -euo pipefail
mods=("wsgiapp/__init__.py" "backend/__init__.py")
for m in "${mods[@]}"; do
  [ -f "$m" ] || continue
  python - <<PY
import py_compile, sys
py_compile.compile("$m", doraise=True)
print("✓ compila:", "$m")
PY
done
