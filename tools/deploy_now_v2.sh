#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
CLEAR="${CLEAR_CACHE:-false}"   # export CLEAR_CACHE=true para limpiar
echo "[probe] Comparando remoto vs HEAD…"
if tools/deploy_probe.sh "$BASE"; then
  echo "OK: remoto ya coincide con HEAD. Nada que hacer."
  exit 0
fi

did_trigger=0
if [[ -n "${RENDER_DEPLOY_HOOK:-}" ]]; then
  echo "[hook] Disparando deploy via hook…"
  tools/deploy_trigger_via_hook.sh || true
  did_trigger=1
fi

if [[ "$did_trigger" -eq 0 && -n "${RENDER_API_KEY:-}" && -n "${RENDER_SERVICE_ID:-}" ]]; then
  echo "[api] Disparando deploy via API (clearCache=${CLEAR})…"
  tools/deploy_trigger_via_api.sh "$CLEAR" || true
  did_trigger=1
fi

if [[ "$did_trigger" -eq 0 ]]; then
  cat >&2 <<MSG
[manual] No hay hook ni credenciales API:
 - Opción A: activá Auto-deploy en Render y hacé un 'Manual Deploy' desde el panel.
 - Opción B: configurá RENDER_DEPLOY_HOOK o RENDER_API_KEY/RENDER_SERVICE_ID y reintentá.
MSG
  exit 2
fi

echo "[watch] Esperando a que remoto == HEAD…"
tools/deploy_watch_until_v4.sh "$BASE" 480

echo "[post] Corriendo negativos para confirmar 404 en inexistente…"
tools/test_suite_negative_v5.sh "$BASE"
