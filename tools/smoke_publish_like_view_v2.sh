#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
echo "== health =="; curl -sS "$BASE/api/health" && echo

TXT="shim smoke $(date -u +%H:%M:%SZ) — 1234567890 abcdefghij texto suficiente"

echo "== create JSON (espera 4xx si 'text_required') =="
curl -sS -H 'Content-Type: application/json' --data "{\"text\":\"$TXT\"}" -D /tmp/h1 -o /tmp/b1 "$BASE/api/notes" || true
code1="$(sed -n '1s/^HTTP\/[0-9.]* //p' /tmp/h1)"
echo "status:$code1"

echo "== create FORM (fallback 201) =="
curl -sS -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "text=$TXT" -D /tmp/h2 -o /tmp/b2 "$BASE/api/notes"
ID=""
if command -v jq >/dev/null 2>&1; then
  ID="$(jq -r '.item.id // .id // empty' < /tmp/b2)"
fi
[ -n "$ID" ] || ID="$(grep -Eo '"id"[[:space:]]*:[[:space:]]*[0-9]+' /tmp/b2 | head -1 | grep -Eo '[0-9]+')"
echo "id=$ID"
[ -n "$ID" ] || { echo "✗ no pude extraer id"; exit 1; }

echo "== like =="; curl -sS -X POST "$BASE/api/notes/$ID/like" && echo
echo "== view =="; curl -sS -X POST "$BASE/api/notes/$ID/view" && echo

echo "== single flag (HTML) =="
curl -sS "$BASE/?id=$ID&_=$(date +%s)&nosw=1" -o /tmp/s1
grep -q 'data-single="1"' /tmp/s1 && echo "OK: data-single" || echo "⚠ sin data-single (frontend igual puede renderizar)"
echo "share-url: $BASE/?id=$ID"
