#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: frontend/runtime AdSense injector + guard}"

git add -f tools/adsense_runtime_injector.sh tools/test_adsense_runtime.sh tools/fix_contract_shim_import_guard.sh || true
git add -f wsgi.py || true

git commit -m "$MSG" || echo "ℹ️  Nada que commitear"
echo "== prepush gate =="
bash -n tools/adsense_runtime_injector.sh && echo "bash -n injector OK"
bash -n tools/test_adsense_runtime.sh && echo "bash -n test OK"
git push origin main
echo "✔ Push OK"
