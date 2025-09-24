#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
MAX="${2:-30}"   # intentos
SLEEP="${3:-2}"  # segundos entre intentos

echo "== Poll deploy =="
for i in $(seq 1 "$MAX"); do
  H="$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/health")" || H=000
  O="$(curl -s -o /dev/null -X OPTIONS -w '%{http_code}' "$BASE/api/notes")" || O=000
  # buscar marca de shim/cohesión sin service worker
  HTML="$(curl -fsS "$BASE/?nosw=1&_=$RANDOM" || true)"
  if [ "$H" = "200" ] && [ "$O" = "204" ] && echo "$HTML" | grep -qiE 'mini[- ]shim|data-ui-shim|cohesi[óo]n'; then
    echo "✓ health=200, preflight=204 y shim detectado en index.html"
    exit 0
  fi
  echo "· intento $i/$MAX (health=$H, options=$O) …"
  sleep "$SLEEP"
done
echo "✗ No se confirmó el despliegue (health/options/shim). Revisa logs."
exit 1
