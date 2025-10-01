#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [secs] [OUTDIR]}"
SECS="${2:-300}"
OUTDIR="${3:-/sdcard/Download}"
ts="$(date -u +%Y%m%d-%H%M%SZ)"
dir="$OUTDIR/post-release-$ts"
mkdir -p "$dir"
log="$dir/watch.log"

probe(){
  code=$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/")
  head=$(curl -fsS -D - "$BASE/" -o /dev/null | tr -d '\r' | sed -n '1,20p')
  dep=$(curl -fsS "$BASE/api/deploy-stamp" 2>/dev/null | sed 's/[[:space:]]\+/ /g' || true)
  meta=$(curl -fsS "$BASE" | sed -n 's/.*name="p12-commit" content="\([0-9a-f]\{7,40\}\)".*/\1/p')
  echo "$(date -u +%H:%M:%S) code=$code meta=${meta:0:7} dep=$(echo "$dep" | sed -n 's/.*\([0-9a-f]\{7,40\}\).*/\1/p' | cut -c1-7) | $(echo "$head" | grep -i '^cache-control:')" | tee -a "$log"
}
t0=$(date +%s)
while :; do
  probe
  (( $(date +%s) - t0 > SECS )) && break
  sleep 10
done
echo "OK: watch → $log"
