#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-${BASE:-http://127.0.0.1:5000}}"
OUTDIR="${2:-${OUTDIR:-./p12-audit}}"
N="${3:-420}"
mkdir -p "$OUTDIR"

echo "-- create $N notes"
for i in $(seq 1 "$N"); do
  curl -sS -X POST "$BASE/api/notes" -H 'Content-Type: application/json' -d "{\"text\":\"n $i\",\"ttlHours\":12}" >/dev/null || true
  if (( i % 50 == 0 )); then echo "$i"; fi
done

count=$(curl -sS "$BASE/api/notes?limit=500" | jq '.notes|length')
echo "count=$count" | tee "$OUTDIR/cap-count.txt"
exit 0