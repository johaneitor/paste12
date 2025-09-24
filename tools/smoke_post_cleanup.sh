#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
echo "== health =="; curl -fsS "$BASE/api/health" && echo
echo "== preflight =="; curl -fsS -o /dev/null -w '%{http_code}\n' -X OPTIONS "$BASE/api/notes"
echo "== index v7 =="; curl -fsS "$BASE/?_=$(date +%s)&nosw=1" | grep -q 'id="p12-cohesion-v7"' && echo "✓ v7" || echo "✗ sin v7"
echo "== list headers =="; curl -fsS -D- "$BASE/api/notes?limit=5" -o /dev/null | sed -n '1,12p' | sed 's/\r$//'
TXT="post-clean —— 1234567890 abcdefghij"
echo "== create (FORM) =="; ID=$(curl -fsS -H 'Content-Type: application/x-www-form-urlencoded' --data-urlencode "text=$TXT" "$BASE/api/notes" | sed -n 's/.*\"id\":[ ]*\([0-9]\+\).*/\1/p'); echo "id=$ID"
echo "== like =="; curl -fsS -X POST "$BASE/api/notes/$ID/like" && echo
echo "== view =="; curl -fsS -X POST "$BASE/api/notes/$ID/view" && echo
echo "== single flag =="; curl -fsS "$BASE/?id=$ID&_=$(date +%s)" | grep -q 'data-single=\"1\"' && echo "✓ data-single" || echo "⚠ sin data-single (frontend igual puede renderizar)"
