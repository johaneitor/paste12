#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
source "$(dirname "$0")/_tmpdir.sh"

hex_head(){ if command -v xxd >/dev/null; then xxd -l 64 -g 1 "$1"; else head -c 64 "$1" | od -An -t x1; fi; }

TMPD="$(mkd)"; trap 'rm -rf "$TMPD"' EXIT
IDX="$TMPD/index.html"

echo "== BE: health ==";    curl -sS "$BASE/api/health" && echo
echo; echo "== BE: preflight (OPTIONS /api/notes) =="; curl -sS -i -X OPTIONS "$BASE/api/notes" | sed -n '1,20p'
echo; echo "== FE: index (sin SW) — tamaño y primeros bytes =="
curl -fsS "$BASE/?nosw=1&_=$(date +%s)" -o "$IDX" || true
printf "bytes=%s\n" "$(wc -c < "$IDX" | tr -d ' ' || echo 0)"
[ -s "$IDX" ] && hex_head "$IDX" || true
echo "marker_safe_shim: $([ -s "$IDX" ] && grep -Fqi 'name=\"p12-safe-shim\"' "$IDX" && echo yes || echo no)"

echo; echo "== BE: list (Link/X-Next-Cursor) =="; curl -sS -i "$BASE/api/notes?limit=3" | sed -n '1,25p'
echo; echo "== BE: publish (FORM fallback) =="; ID=$(curl -fsS -H 'Content-Type: application/x-www-form-urlencoded' --data-urlencode "text=trace $(date -u +%H:%M:%SZ) — 1234567890 abcdefghij" "$BASE/api/notes" | sed -n 's/.*\"id\":[ ]*\([0-9]\+\).*/\1/p'); echo "id=$ID"
echo "== BE: like/view =="; curl -sS -X POST "$BASE/api/notes/$ID/like" && echo; curl -sS -X POST "$BASE/api/notes/$ID/view" && echo
echo "== FE: single-by-id (sin SW) — meta/body =="
H="$(curl -fsS "$BASE/?id=$ID&nosw=1&_=$(date +%s)")"
if echo "$H" | tr -d '\n' | grep -Fqi '<meta name="p12-single"'; then echo "OK meta"; elif echo "$H" | tr -d '\n' | grep -Fqi 'data-single="1"'; then echo "OK body"; else echo "X sin single"; fi
