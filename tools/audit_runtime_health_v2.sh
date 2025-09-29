#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# Carga BASE desde .env si existe
if [[ -f "$HERE/env_load.sh" ]]; then . "$HERE/env_load.sh"; fi
: "${BASE:?Definí BASE, ej: https://paste12-rmsk.onrender.com}"
OUT="$("$HERE/_resolve_outdir.sh")"; mkdir -p "$OUT"
TS="$(date -u +%Y%m%d-%H%M%SZ)"

{
  echo "# deploy_probe_v2"; "$HERE/deploy_probe_v2.sh" "$BASE" || true
} | tee "$OUT/runtime-deploy-$TS.txt" >/dev/null

{
  echo "# test_suite_all"; "$HERE/test_suite_all.sh" "$BASE" || true
} | tee "$OUT/runtime-positive-$TS.txt" >/dev/null

{
  echo "# test_suite_negative_v5"; "$HERE/test_suite_negative_v5.sh" "$BASE" || true
} | tee "$OUT/runtime-negative-$TS.txt" >/dev/null

echo "Artefactos en: $OUT"
ls -1 "$OUT"/runtime-*"$TS"*.txt 2>/dev/null | sed 's/^/  /' || true

# Aviso si OUT no es sdcard
case "$OUT" in
  *storage/downloads*|*/sdcard/Download/*|*/emulated/0/Download/*) : ;;
  *) echo "NOTE: OUT=$OUT no es sdcard. Corré 'termux-setup-storage' para habilitar ~/storage/downloads." >&2 ;;
esac
