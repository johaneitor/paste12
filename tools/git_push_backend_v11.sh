#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: backend v11 (tests GET Link + push helpers)}"

echo "== prepush gate =="
python - <<'PY'
import py_compile, sys
for f in ("contract_shim.py","wsgi.py","tools/test_exec_backend_v11.sh"):
    try: py_compile.compile(f, doraise=True)
    except Exception as e:
        print("py_compile FAIL:", f, e); sys.exit(1)
print("py_compile OK")
PY

git add -f contract_shim.py wsgi.py tools/test_exec_backend_v11.sh tools/git_push_backend_v11.sh
git commit -m "$MSG" || echo "ℹ️  Nada que commitear"
git push origin main

echo "== Post-push =="
echo "Local : $(git rev-parse HEAD)"
echo "Remote: $(git ls-remote origin -h refs/heads/main | cut -f1)"
