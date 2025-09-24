#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: tools/test_exec_backend_v5.sh https://app.onrender.com}"

echo "== Smoke básico =="
tools/test_suite_all.sh "$BASE" || true
echo
echo "== Negativos (404 esperados) =="
tools/test_suite_negative_v5.sh "$BASE" || true
echo
echo "== Like/View (no 404 en existentes) =="
tools/test_like_view.sh "$BASE" || true
echo
echo "== Reported count (no fatal) =="
tools/check_reported_count.sh "$BASE" || true
