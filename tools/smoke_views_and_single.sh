#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
say(){ echo -e "$*"; }

say "== Crear nota (FORM) =="
TXT="vista/share $(date -u +%H:%M:%SZ) 1234567890 abcdefghij"
ID=$(curl -fsS -X POST "$BASE/api/notes" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "text=$TXT" \
  | sed -n 's/.*"id":[ ]*\([0-9]\+\).*/\1/p')
echo "id=$ID"

say "== GET nota por id (JSON) =="
curl -fsS "$BASE/api/notes/$ID" | sed -n '1,120p'

say "== POST /view (incrementa) =="
curl -fsS -X POST "$BASE/api/notes/$ID/view" -H 'X-FP: test' | sed -n '1,120p'

say "== Verifica contador (JSON) =="
curl -fsS "$BASE/api/notes/$ID" | sed -n '1,120p'

say "== HTML de nota única (/?id=) =="
curl -fsS "$BASE/?id=$ID&nosw=1" | sed -n '1,120p'
