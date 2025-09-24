#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
pick(){ for d in "/sdcard/Download" "/storage/emulated/0/Download" "$HOME/Download" "$HOME/downloads"; do [ -d "$d" ] && [ -w "$d" ] && { echo "$d"; return; }; done; echo "$HOME"; }
DEST="$(pick)"; TS="$(date -u +%Y%m%d-%H%M%SZ)"; OUT="$DEST/backend-audit-$TS.txt"
{
  echo "base: $BASE"
  echo "== /api/health ==";        curl -sS "$BASE/api/health"; echo
  echo "== OPTIONS /api/notes =="; curl -sS -i -X OPTIONS "$BASE/api/notes" | sed -n '1,40p'
  echo "== GET /api/notes?limit=3 =="; curl -sS -i "$BASE/api/notes?limit=3" | sed -n '1,60p'
  echo "== NEGATIVOS: like/view/report 999999 =="; for ep in like view report; do printf "%-6s -> " "$ep"; curl -sS -o /dev/null -w "%{http_code}\n" -X POST "$BASE/api/notes/999999/$ep"; done
} >"$OUT"
echo "OK: $OUT"
