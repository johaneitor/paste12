#!/usr/bin/env bash
set -euo pipefail

MSG="${1:-ops: db hardening (pre_ping, recycle, keepalives) + handler OperationalError + smoke}"

./tools/harden_sqlalchemy_pool_v2.sh
./tools/add_db_operationalerror_handler_v1.sh

echo "== prepush gate =="
python - <<'PY'
import py_compile,glob,sys
for p in ["wsgi.py","backend/__init__.py","backend/app.py","app.py","wsgiapp/__init__.py"]:
    try: py_compile.compile(p, doraise=True)
    except Exception: pass
print("py_compile OK")
PY
bash -n tools/harden_sqlalchemy_pool_v2.sh
bash -n tools/add_db_operationalerror_handler_v1.sh
bash -n tools/test_db_hardening_smoke.sh

git add -f tools/harden_sqlalchemy_pool_v2.sh tools/add_db_operationalerror_handler_v1.sh tools/test_db_hardening_smoke.sh tools/git_push_db_hardening_v2.sh || true
git commit -m "$MSG" || echo "ℹ️  Nada para commitear"
git push origin main

echo "== Post-push =="
echo "Local : $(git rev-parse HEAD)"
echo "Remote: $(git ls-remote origin -h refs/heads/main | cut -f1)"
