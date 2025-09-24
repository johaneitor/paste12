#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
say(){ echo -e "$*"; }

say "== health =="; curl -fsS "$BASE/api/health"; echo
say "== list ==";   curl -fsS "$BASE/api/notes?limit=3"; echo

TEXT="ui shim smoke $(date -u +%H:%M:%SZ) 1234567890 abcdefghij texto válido"
say "== create (JSON) ==";
set +e
RESP="$(curl -s -w '\n%{http_code}' -H 'Content-Type: application/json' --data-binary "$(printf '{"text":"%s"}' "$TEXT")" "$BASE/api/notes")"
BODY="$(echo "$RESP" | sed '$d')"; CODE="$(echo "$RESP" | tail -n1)"
set -e
echo "code=$CODE"
echo "$BODY"

if [ "$CODE" != "200" ] && [ "$CODE" != "201" ]; then
  say "== create (FORM fallback) =="
  RESP="$(curl -s -w '\n%{http_code}' -H 'Content-Type: application/x-www-form-urlencoded' --data "text=$(printf %s "$TEXT" | sed 's/ /+/g')" "$BASE/api/notes")"
  BODY="$(echo "$RESP" | sed '$d')"; CODE="$(echo "$RESP" | tail -n1)"
  echo "code=$CODE"
  echo "$BODY"
fi
