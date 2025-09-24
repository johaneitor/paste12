#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
REF="${REF:-origin/main}"
CLEAR="${CLEAR_CACHE:-true}"

echo "[probe] remoto vs $REF"
if tools/deploy_probe_ref.sh "$BASE" "$REF"; then
  echo "OK: remoto ya coincide con $REF. Nada que hacer."
  exit 0
fi

if [[ -n "${RENDER_API_KEY:-}" && -n "${RENDER_SERVICE_ID:-}" ]]; then
  echo "[api] Disparando deploy (clearCache=${CLEAR})…"
  tools/deploy_trigger_via_api.sh "$CLEAR" || true
else
  cat >&2 <<MSG
[manual] No hay API KEY / SERVICE ID:
 - Configurá RENDER_API_KEY y RENDER_SERVICE_ID (o hacé 'Manual Deploy' + 'Clear build cache' en el Dashboard).
MSG
fi

echo "[watch] Esperando a que remoto == $REF…"
tools/deploy_watch_until_ref.sh "$BASE" "$REF" 480

echo "[post] Suite negativa para confirmar 404/404/404"
tools/test_suite_negative_v5.sh "$BASE"
