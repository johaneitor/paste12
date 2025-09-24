#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
# “Kick” opcional (si Render no detecta cambio)
git commit --allow-empty -m "chore: trigger render"
git push origin main

echo "➡️  Ahora en dashboard.render.com:"
echo "   - Si tu servicio es Blueprint: Sync/Deploy (con Clear build cache)"
echo "   - Si es manual: Settings → Start Command ="
echo "     gunicorn entry_main:app --chdir /opt/render/project/src -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} --timeout \${TIMEOUT:-120} -b 0.0.0.0:\$PORT"
echo "     y 'Save, rebuild, and deploy' con Clear build cache."
echo "   - En Environment NO debe haber APP_MODULE / P12_WSGI_*"

# Esperar hasta que /api/deploy-stamp matchee HEAD
tools/deploy_watch_until_v4.sh "$BASE" 480 || true

# Suites
tools/test_suite_all.sh "$BASE"
tools/test_suite_negative_v5.sh "$BASE" || true

# Auditorías
tools/audit_deploy_env_v3.sh "$BASE"
tools/audit_backend_to_sdcard_v3.sh "$BASE"
tools/audit_fe_be_to_sdcard_v3.sh "$BASE"
