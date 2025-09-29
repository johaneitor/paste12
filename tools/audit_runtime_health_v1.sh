#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/../tools/env_load.sh"
TS="$(date -u +%Y%m%d-%H%M%SZ)"; OUT="${HOME}/Download"; mkdir -p "$OUT"
{
  echo "# deploy_probe_v2"; "$HERE/deploy_probe_v2.sh" "$BASE" || true
} | tee "$OUT/runtime-deploy-$TS.txt"
{
  echo "# test_suite_all"; "$HERE/test_suite_all.sh" "$BASE" || true
} | tee "$OUT/runtime-positive-$TS.txt"
{
  echo "# test_suite_negative_v5"; "$HERE/test_suite_negative_v5.sh" "$BASE" || true
} | tee "$OUT/runtime-negative-$TS.txt"
echo "Artefactos en $OUT:"
ls -1 "$OUT"/*"$TS"*
