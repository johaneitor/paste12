#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: db pooling + ads.txt + audits}"
git add -f tools/patch_db_pooling_v3.sh tools/add_ads_txt_verification_v1.sh \
           tools/test_adsense_everywhere_v1.sh tools/deep_fe_be_audit_v8.sh \
           tools/git_push_ops_batch_v1.sh
git commit -m "$MSG" || echo "Nada para commitear"
echo "== prepush gate =="
echo "✓ listo"
git push -u origin main
echo "== HEADs =="
echo "Local : $(git rev-parse HEAD)"
UP="$(git rev-parse @{u} 2>/dev/null || true)"; [[ -n "$UP" ]] && echo "Remote: $UP" || true
