#!/usr/bin/env bash
# Uso: tools/probe_500_details.sh "https://paste12-rmsk.onrender.com" "/api/notes?limit=10"
set -euo pipefail
BASE="${1:-}"; PATHQ="${2:-/api/notes?limit=10}"
[ -n "$BASE" ] || { echo "Falta BASE"; exit 2; }
ts="$(date -u +%Y%m%d-%H%M%SZ)"
out="probe-$(echo "$PATHQ" | tr '/?&=' '_')-$ts.txt"
curl -isS "$BASE$PATHQ" -H 'Accept: application/json' -o "$out" || true
echo "OK: $out"
sed -n '1,50p' "$out"
