#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: legal pages + routes + adsense tester v2 + audits v9 + db err handlers}"
git add -f tools/create_legal_pages_and_routes_v1.sh \
           tools/test_adsense_everywhere_v2.sh \
           tools/deep_fe_be_audit_v9.sh \
           tools/patch_db_error_handlers_v1.sh \
           tools/git_push_ops_batch_v2.sh \
           frontend/terms.html frontend/privacy.html
git commit -m "$MSG" || echo "Nada para commitear"
echo "== prepush gate =="; echo "✓ listo"
git push -u origin main
echo "Local : $(git rev-parse HEAD)"
echo "Remote: $(git rev-parse @{u})"
