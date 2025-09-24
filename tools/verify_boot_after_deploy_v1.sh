#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
TRIES="${3:-40}"         # 40 intentos
SLEEP_SECS="${4:-3}"     # cada 3s
TS="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p "$OUT"

echo "== verify_boot_after_deploy_v1 =="
echo "BASE=$BASE  TRIES=$TRIES  SLEEP=$SLEEP_SECS"
LOG="$OUT/boot-health-$TS.log"
: > "$LOG"

ok=0
for ((i=1;i<=TRIES;i++)); do
  code="$(curl -sS -o "$OUT/health-$TS.json" -w "%{http_code}" "$BASE/api/health" || true)"
  echo "[$(date -u +%H:%M:%S)] try=$i code=$code" | tee -a "$LOG"
  if [[ "$code" == "200" ]]; then
    echo "OK: /api/health=200 (guardado: $OUT/health-$TS.json)" | tee -a "$LOG"
    ok=1; break
  fi
  sleep "$SLEEP_SECS"
done

echo "Log: $LOG"
if [[ "$ok" != "1" ]]; then
  echo "FAIL: salud no llegó a 200 a tiempo."
  exit 1
fi
