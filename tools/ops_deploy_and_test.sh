#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "uso: $0 https://host [--timeout S] [--no-trigger] [--strict]"
  echo " vars: RENDER_DEPLOY_HOOK=URL (opcional, si querés autodesplegar)"
}

BASE=""; TIMEOUT=480; NO_TRIGGER=0; STRICT=0
while [ $# -gt 0 ]; do
  case "$1" in
    http*) BASE="$1"; shift;;
    --timeout) TIMEOUT="${2:-480}"; shift 2;;
    --no-trigger) NO_TRIGGER=1; shift;;
    --strict) STRICT=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "arg desconocido: $1"; usage; exit 2;;
  esac
done
[ -n "$BASE" ] || { usage; exit 2; }

echo "== Contexto =="
echo " BASE     : $BASE"
echo " TIMEOUT  : $TIMEOUT s"
echo " STRICT   : $STRICT (falla si negativos no dan 404)"
echo " HEAD     : $(git rev-parse --short HEAD)"
echo

echo "== 1) Probe deploy actual =="
if tools/deploy_probe.sh "$BASE"; then
  echo "✓ remoto ya está en HEAD"
else
  echo "… remoto desfasado"
  if [ $NO_TRIGGER -eq 0 ] && [ -n "${RENDER_DEPLOY_HOOK:-}" ]; then
    echo "== 2) Trigger redeploy via hook =="
    tools/deploy_trigger_via_hook.sh
  else
    echo "≡ saltando trigger (NO_TRIGGER=$NO_TRIGGER, hook=${RENDER_DEPLOY_HOOK:+set}${RENDER_DEPLOY_HOOK:-unset})"
  fi
  echo "== 3) Esperar hasta HEAD =="
  tools/deploy_watch_until_v4.sh "$BASE" "$TIMEOUT"
fi

echo "== 4) Verificación integral (suites + auditorías) =="
tools/ci_verify_all_v2.sh "$BASE"

echo "== 5) Suite negativa (estricta opcional) =="
NEG_STATUS=0
if [ $STRICT -eq 1 ]; then
  tools/test_suite_negative_v5.sh "$BASE" || NEG_STATUS=$?
  [ $NEG_STATUS -eq 0 ] && echo "✓ negativos OK (404 en like/view/report)" || { echo "✗ negativos FAIL"; exit $NEG_STATUS; }
else
  tools/test_suite_negative_v5.sh "$BASE" || true
fi

echo "== 6) Listo =="
echo "Los informes fueron guardados en /sdcard/Download/ por los scripts de auditoría."
