#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
say(){ echo -e "$*"; }

say "== health =="; curl -sS "$BASE/api/health" && echo

say "== index bytes (sin SW) =="; BYTES=$(curl -fsS "$BASE/?nosw=1&_=$(date +%s)" | wc -c | tr -d ' '); echo "bytes=$BYTES"

say "== list (peek, Link) ==";
HDRS=$(curl -sS -D - "$BASE/api/notes?limit=3" -o /dev/null)
echo "$HDRS" | sed -n '1,20p' | grep -i '^link:' || true
NEXT=$(echo "$HDRS" | sed -n 's/^link:\s*<\([^>]*\)>;.*$/\1/ip' | head -n1)

say "== publish (JSON->FORM fallback) ==";
NEW=$(curl -fsS -H 'Content-Type: application/json' --data '{"text":"shim v1.1 — 1234567890 abcdefghij texto largo"}' "$BASE/api/notes" \
  | sed -n 's/.*"id":[ ]*\([0-9]\+\).*/\1/p' || true)
if [ -z "$NEW" ]; then
  NEW=$(curl -fsS -H 'Content-Type: application/x-www-form-urlencoded' --data-urlencode "text=shim v1.1 — 1234567890 abcdefghij texto largo" "$BASE/api/notes" \
    | sed -n 's/.*"id":[ ]*\([0-9]\+\).*/\1/p' || true)
fi
echo "id=$NEW"

say "== like/view ==";
curl -sS -X POST "$BASE/api/notes/$NEW/like" && echo
curl -sS -X POST "$BASE/api/notes/$NEW/view" && echo

say "== paginación (si hay Link) ==";
[ -n "$NEXT" ] && curl -sS "$BASE$NEXT" | jq -r '.items[]?.id' 2>/dev/null | head -n3 || echo "(sin next)"

say "== single-share URL =="
echo "$BASE/?id=$NEW&nosw=1"
