#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: backend v11 (tests GET Link + push helpers, prepush gate fix)}"

echo "== prepush gate =="
python - <<'PY'
import py_compile, sys
for f in ("contract_shim.py","wsgi.py"):
    try:
        py_compile.compile(f, doraise=True)
    except Exception as e:
        print("py_compile FAIL:", f, e); sys.exit(1)
print("py_compile OK")
PY

# Lint de shell (silencioso si no existen)
for f in tools/test_exec_backend_v11.sh tools/test_exec_backend_v11a.sh tools/git_push_backend_v11_fix.sh; do
  [ -f "$f" ] && bash -n "$f"
done
echo "bash -n OK"

git add -f contract_shim.py wsgi.py \
  tools/test_exec_backend_v11a.sh tools/git_push_backend_v11_fix.sh || true

git commit -m "$MSG" || echo "ℹ️  Nada que commitear"
git push origin main

echo "== Post-push =="
LOCAL_SHA="$(git rev-parse HEAD)"
REMOTE_SHA="$(git ls-remote origin -h refs/heads/main | cut -f1)"
echo "Local : $LOCAL_SHA"
echo "Remote: $REMOTE_SHA"
[ "$LOCAL_SHA" = "$REMOTE_SHA" ] && echo "✔ Remote actualizado" || { echo "⚠ Desfase entre local y remoto"; exit 1; }
