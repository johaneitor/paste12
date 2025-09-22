#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
OUT="${2:-/sdcard/Download}"
ts="$(date -u +%Y%m%d-%H%M%SZ)"
be="$OUT/backend-audit-$ts.txt"
fe="$OUT/frontend-audit-$ts.txt"
ix="$OUT/index-$ts.html"

# Backend
{
  echo "base: $BASE"
  echo "== /api/health =="; curl -fsS "$BASE/api/health"; echo -e "\n"
  echo "== OPTIONS /api/notes =="; curl -fsS -i -X OPTIONS "$BASE/api/notes"; echo
  echo "== GET /api/notes?limit=10 =="; curl -fsS -i "$BASE/api/notes?limit=10"; echo
  echo "== NEGATIVOS: like/view/report 999999 =="; 
  for p in like view report; do
    printf "%-7s -> " "$p"
    curl -s -o /dev/null -w '%{http_code}\n' -X POST "$BASE/api/notes/999999/$p"
  done
} > "$be"
echo "OK: $be"

# Frontend
curl -fsS "$BASE/" -o "$ix" && echo "OK: $ix"
{
  echo "== checks de frontend =="
  bytes=$(wc -c <"$ix"); echo "index bytes=$bytes"
  grep -q '<section class="list" id="list">' "$ix" && echo "list presente"
  grep -q 'class="meta"' "$ix" && echo "meta presente"
  grep -qi 'googleads' "$ix" && echo "adsense detectado (si corresponde)" || echo "adsense ausente (tolerado)"
} > "$fe"
echo "OK: $fe"
