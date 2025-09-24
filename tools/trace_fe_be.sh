#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
TS="$(date -u +%s)"
echo "== BE: health =="; curl -sS "$BASE/api/health" && echo
echo; echo "== BE: preflight (OPTIONS /api/notes) =="; curl -sS -i -X OPTIONS "$BASE/api/notes" | sed -n '1,20p'
TMP="/tmp/idx.$$"; curl -fsS "$BASE/?nosw=1&_=$TS" -o "$TMP.a" || true
echo; echo "== FE: index (sin SW) — tamaño y primeros bytes =="
[ -s "$TMP.a" ] && { echo "bytes=$(wc -c < "$TMP.a" | tr -d ' ')"; head -c 80 "$TMP.a" | hexdump -C | sed -n '1,3p'; } || echo "bytes=0"
echo "marker_v7: no"; echo "marker_safe_shim: $(grep -qi 'name=\"p12-safe-shim\"' "$TMP.a" && echo yes || echo no)"
echo; echo "== BE: list (Link/X-Next-Cursor) =="; curl -sS -i "$BASE/api/notes?limit=3" | sed -n '1,20p'; curl -sS "$BASE/api/notes?limit=3"
echo; echo "== BE: publish (FORM fallback) =="; ID=$(curl -fsS -H 'Content-Type: application/x-www-form-urlencoded' --data-urlencode "text=audit $TS — 1234567890 abcdefghij texto suficientemente largo" "$BASE/api/notes" | sed -n 's/.*"id":[ ]*\([0-9]\+\).*/\1/p'); echo "id=$ID"
echo "== BE: like/view =="; curl -sS -X POST "$BASE/api/notes/$ID/like"; echo; curl -sS -X POST "$BASE/api/notes/$ID/view"; echo
echo "== FE: single-by-id (sin SW) — meta p12-single =="; curl -sS "$BASE/?id=$ID&nosw=1&_=$TS" | grep -qi 'name="p12-single"' && echo "OK single-meta" || echo "X sin single-meta"
rm -f "$TMP.a" || true
