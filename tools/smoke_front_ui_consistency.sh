#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
TMP="${TMPDIR:-/tmp}/uismoke.$$"; mkdir -p "$TMP"
echo "== HEALTH =="; curl -fsS "$BASE/api/health"; echo; echo "---------------------------------------------"

echo "== Publish (API) ==";
ID="$(printf '{"text":"ui smoke %s 1234567890"}' "$(date -u +%H:%M:%SZ)" |
  curl -fsS -H 'Content-Type: application/json' --data-binary @- "$BASE/api/notes" |
  { command -v jq >/dev/null && jq -r '.item.id // .id' || sed -n 's/.*"id":\s*\([0-9]\+\).*/\1/p'; })"
echo "id=$ID"; echo "---------------------------------------------"

echo "== Página 1 / 2 / 3 (API) =="
curl -fsS "$BASE/api/notes?limit=5" -D "$TMP.h1" -o "$TMP.b1" >/dev/null || true
echo "p1: $(sed -n '1p' "$TMP.h1")"; grep -o '"id":[0-9]\+' "$TMP.b1" | head | tr -d '"' | tr ':' ' ' | awk '{print $2}' | sed 's/^/id: /'
NEXT="$(sed -n 's/^[Ll]ink:\s*<\([^>]*\)>.*/\1/p' "$TMP.h1")"
if [ -n "$NEXT" ]; then
  curl -fsS "$BASE$NEXT" -D "$TMP.h2" -o "$TMP.b2" >/dev/null || true
  echo "p2: $(sed -n '1p' "$TMP.h2")"; grep -o '"id":[0-9]\+' "$TMP.b2" | tr -d '"' | tr ':' ' ' | awk '{print $2}' | sed 's/^/id: /' | head
  NEXT2="$(sed -n 's/^[Ll]ink:\s*<\([^>]*\)>.*/\1/p' "$TMP.h2")"
  if [ -n "$NEXT2" ]; then
    curl -fsS "$BASE$NEXT2" -D "$TMP.h3" -o "$TMP.b3" >/dev/null || true
    echo "p3: $(sed -n '1p' "$TMP.h3")"; grep -o '"id":[0-9]\+' "$TMP.b3" | tr -d '"' | tr ':' ' ' | awk '{print $2}' | sed 's/^/id: /' | head
  fi
fi
echo "TMP: $TMP"
