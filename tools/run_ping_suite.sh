#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"

echo "== run_ping_suite @ $BASE =="
tools/force_wsgi_ping_early.sh
tools/verify_wsgi_patch.sh || true

echo "-- Poke redeploy --"
tools/poke_redeploy.sh

echo "-- Espera a que /__version responda (hasta 40 x 3s) --"
ok=0
for i in $(seq 1 40); do
  code="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/__version" || true)"
  [[ "$code" == "200" ]] && { ok=1; break; }
  printf "aún=%s  " "$code"
  sleep 3
done
echo
[[ $ok == 1 ]] || echo "WARN: /__version no 200 (igual seguimos)"

echo
tools/show_version_and_routes.sh "$BASE"
echo
tools/smoke_ping_diag.sh "$BASE" || true

echo
echo "== Resumen:"
echo " - Si /api/ping sigue 404 y /api/_routes no lo lista, Render no tomó el wsgi con early-pin."
echo " - En ese caso, corré: tools/force_rebuild_marker.sh y repetí esta suite."
