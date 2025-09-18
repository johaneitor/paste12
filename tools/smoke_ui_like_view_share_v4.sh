#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
echo "== health =="; curl -sS "$BASE/api/health" && echo
J="ui smoke $(date -u +%H:%M:%SZ) —— 1234567890 abcdefghij texto largo"
ID=$(curl -fsS -H 'Content-Type: application/x-www-form-urlencoded' --data-urlencode "text=$J" "$BASE/api/notes" | sed -n 's/.*"id":[ ]*\([0-9]\+\).*/\1/p')
echo "id=$ID"
echo "== like ==";  curl -sS -X POST "$BASE/api/notes/$ID/like" && echo
echo "== view ==";  curl -sS -X POST "$BASE/api/notes/$ID/view" && echo
echo "== single (HTML flags por meta) =="; curl -sS "$BASE/?id=$ID&nosw=1&_=$(date +%s)" | grep -qi 'name="p12-single"' && echo "OK single-meta" || echo "⚠ meta p12-single no detectada (visualiza manualmente)"
echo "share-url: $BASE/?id=$ID"
