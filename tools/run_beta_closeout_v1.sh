#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
DL="${HOME}/Download"; mkdir -p "$DL"
TMP="${HOME}/.tmp_p12"; mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

echo "[1/4] Probe de deploy"
tools/deploy_probe.sh "$BASE" || {
  echo "Remoto != local; intento de redeploy si hay hook…"
  [[ -n "${RENDER_DEPLOY_HOOK:-}" ]] && tools/deploy_trigger_via_hook.sh
  tools/deploy_watch_until_v4.sh "$BASE" 480
}

echo "[2/4] Test suite (positivos)"
tools/test_suite_all.sh "$BASE"

echo "[3/4] Test suite (negativos esperados 404)"
set +e
neg="$(tools/test_suite_negative_v5.sh "$BASE" 2>&1)"
code=$?
set -e
echo "$neg" | tee "${DL}/negativos-$(date -u +%Y%m%d-%H%M%SZ).log"
LIKE404=$(echo "$neg" | grep -E 'like[^0-9]*->[^0-9]*404' -c || true)
VIEW404=$(echo "$neg" | grep -E 'view[^0-9]*->[^0-9]*404' -c || true)
REPORT404=$(echo "$neg" | grep -E 'report[^0-9]*->[^0-9]*404' -c || true)

echo "[4/4] Auditorías a disco"
tools/audit_backend_to_sdcard_v3.sh "$BASE"
tools/audit_frontend_to_sdcard_v3.sh "$BASE"
tools/audit_fe_be_to_sdcard_v3.sh "$BASE"
tools/audit_deploy_env_v3.sh "$BASE"

echo
echo "Resumen negativos: like= $LIKE404, view= $VIEW404, report= $REPORT404 (1=OK,0=KO)"
if [[ "$LIKE404" != "1" || "$REPORT404" != "1" ]]; then
  echo "ATENCIÓN: like/report no devuelven 404 en inexistente."
  echo "Si el deploy ya está sincronizado y sigue fallando, aplicar el parche BE y repetir."
fi
