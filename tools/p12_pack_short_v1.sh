#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR] }"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
DIR="$OUT/p12-pack-$TS"
mkdir -p "$DIR"

# 1) Live vs local (si está disponible)
tools/live_vs_local_v1.sh "$BASE" "$DIR" >/dev/null 2>&1 || true

# 2) Verificador integral
tools/verify_all_behaviors_v6.sh "$BASE" "$DIR" || true

# 3) Health / runtime simple
tools/quick_smoke_now_v1.sh "$BASE" "$DIR" >/dev/null 2>&1 || true

# Consolidar a 10 archivos máx: elegimos los 5 principales y 5 auxiliares
keep=(
  "$DIR"/live-vs-local-*-summary.txt
  "$DIR"/verify-*-summary.txt
  "$DIR"/verify-*-positivos.txt
  "$DIR"/verify-*-negativos.txt
  "$DIR"/verify-*-limits.txt
  "$DIR"/runtime-*.txt
  "$DIR"/index-remote.html
)
i=0
for f in $(ls -1t "${keep[@]}" 2>/dev/null | head -10); do
  cp -f "$f" "$DIR"/
  i=$((i+1))
done

echo "OK: pack en $DIR ($(ls -1 $DIR | wc -l) archivos)"
