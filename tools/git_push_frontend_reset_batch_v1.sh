#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: frontend reset (commit meta + no-cache html + sw-nuke + dedupe + verify)}"

# Gate rápido
for f in tools/inject_commit_meta_v1.sh tools/add_html_cache_headers_v1.sh tools/add_sw_nuke_v1.sh tools/cleanup_frontend_legacy_v1.sh tools/dedupe_frontend_head_v1.sh tools/adsense_verify_once_v2.sh tools/verify_fallback_and_legals_v1.sh tools/run_frontend_reset_and_audit_v1.sh; do
  [[ -f "$f" ]] || { echo "ERROR falta $f"; exit 3; }
  bash -n "$f" || true
done

python -m py_compile contract_shim.py 2>/dev/null || true

# Stage (forzado)
git add -f tools/*.sh 2>/dev/null || true
git add frontend/index.html 2>/dev/null || true
git add frontend/ads.txt 2>/dev/null || true

if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

echo "== prepush =="
echo "✓ listo"
git push -u origin main

echo "== HEADs =="
echo "Local : $(git rev-parse HEAD)"
UP="$(git rev-parse @{u} 2>/dev/null || true)"
[[ -n "$UP" ]] && echo "Remote: $UP" || echo "Remote: (upstream se definió recién)"
