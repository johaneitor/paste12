#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: backend v9 tests & exporter estable}"
git add tools/test_exec_backend_v8.sh tools/download_results_texts_v2.sh || true
git status --porcelain
if ! git diff --cached --quiet; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada que commitear"
fi
git push origin main
