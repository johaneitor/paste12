#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }

say(){ echo -e "$*"; }
req(){ curl -sS -D "$TMP.h" -o "$TMP.b" "$@" || true; }
hdr(){ sed -n '1,20p' "$TMP.h"; }
body(){ cat "$TMP.b"; }
code(){ sed -n '1s/^.* \([0-9][0-9][0-9]\).*/\1/p' "$TMP.h"; }

TMP="${TMPDIR:-/tmp}/smk.$$.tmp"; mkdir -p "${TMP%/*}"

TS="$(date -u +%H:%M:%SZ)"
PAY="shim v5 smoke ${TS} — 1234567890 abcdefghij (texto de prueba largo)"

say "== health =="
req -H 'Accept: application/json' "$BASE/api/health"; hdr; body; echo

say "== create (JSON) =="
printf '%s' "{\"text\":\"$PAY\"}" > "$TMP.json"
req -H 'Content-Type: application/json' -H 'Accept: application/json' --data-binary @"$TMP.json" "$BASE/api/notes"
C1="$(code)"; echo "code=$C1"; body; echo

if [ "$C1" -ge 200 ] && [ "$C1" -lt 300 ]; then
  ID="$(sed -n 's/.*"id":\s*\([0-9]\+\).*/\1/p' "$TMP.b")"
else
  say "== create (FORM fallback) =="
  req -H 'Content-Type: application/x-www-form-urlencoded' -H 'Accept: application/json' \
      --data-urlencode "text=$PAY" "$BASE/api/notes"
  C2="$(code)"; echo "code=$C2"; body; echo
  ID="$(sed -n 's/.*"id":\s*\([0-9]\+\).*/\1/p' "$TMP.b")"
fi

[ -n "${ID:-}" ] || { echo "✗ no obtuve id (revisa el body de arriba)"; exit 1; }
echo "id=$ID"

say "== like =="
req -H 'Accept: application/json' -X POST "$BASE/api/notes/$ID/like"
echo "code=$(code)"; body; echo

say "== view =="
req -H 'Accept: application/json' -X POST "$BASE/api/notes/$ID/view"
echo "code=$(code)"; body; echo

say "== single-note HTML flag =="
HTML="$(curl -sS "$BASE/?id=$ID&nosw=1")"
echo "$HTML" | grep -q 'data-single="1"' && echo "✓ single flag" || echo "⚠ sin flag"

say "== share url =="
echo "$BASE/?id=$ID"
