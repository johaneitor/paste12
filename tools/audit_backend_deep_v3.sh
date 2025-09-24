#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
source "$(dirname "$0")/_p12_common.sh"
DEST="$(pick_download)"; TS="$(stamp_utc)"; OUT="$DEST/backend-audit-$TS.txt"

{
  echo "base: $BASE"
  echo "== /api/health =="
  curl -sS "$BASE/api/health"; echo

  echo; echo "== OPTIONS /api/notes (CORS) =="
  curl -sS -i -X OPTIONS "$BASE/api/notes" | sed -n '1,30p'

  echo; echo "== GET /api/notes?limit=3 (paginación) =="
  curl -sS -i "$BASE/api/notes?limit=3" | sed -n '1,30p'

  echo; echo "== Publish JSON & FORM =="
  JID=$(curl -fsS -H 'Content-Type: application/json' \
        --data '{"text":"audit json —— 1234567890 abcdefghij"}' "$BASE/api/notes" | sed -n 's/.*"id":[ ]*\([0-9]\+\).*/\1/p'); echo "json_id=$JID"
  FID=$(curl -fsS -H 'Content-Type: application/x-www-form-urlencoded' \
        --data-urlencode "text=audit form —— 1234567890 abcdefghij" "$BASE/api/notes" | sed -n 's/.*"id":[ ]*\([0-9]\+\).*/\1/p'); echo "form_id=$FID"

  echo; echo "== like/view sobre $FID =="
  curl -sS -X POST "$BASE/api/notes/$FID/like"; echo
  curl -sS -X POST "$BASE/api/notes/$FID/view"; echo

  echo; echo "== Negativos: POST vacío y like/view 999999 =="
  curl -sS -i -H 'Content-Type: application/x-www-form-urlencoded' "$BASE/api/notes" --data '' | sed -n '1,12p'
  curl -sS -i -H 'Content-Type: application/json' "$BASE/api/notes" --data '{}' | sed -n '1,12p'
  for ep in like view report; do
    echo "-- $ep inexistente --"
    curl -sS -i -X POST "$BASE/api/notes/999999/$ep" | sed -n '1,12p'
  done
} > "$OUT" || true

echo "OK: $OUT"
