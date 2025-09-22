#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: db hardening v3 (pre_ping/recycle/keepalives) + OperationalError handler + smoke v2}"

./tools/harden_sqlalchemy_pool_v3.sh
./tools/add_db_operationalerror_handler_v1.sh

echo "== prepush =="
bash -n tools/harden_sqlalchemy_pool_v3.sh
bash -n tools/add_db_operationalerror_handler_v1.sh
bash -n tools/test_db_hardening_smoke_v2.sh || true

git add -f tools/harden_sqlalchemy_pool_v3.sh tools/add_db_operationalerror_handler_v1.sh tools/test_db_hardening_smoke_v2.sh tools/git_push_db_hardening_v3.sh
git commit -m "$MSG" || echo "ℹ️  Nada para commitear"
git push origin main

echo "== SHAs =="
echo "Local : $(git rev-parse HEAD)"
echo "Remote: $(git ls-remote origin -h refs/heads/main | cut -f1)"
