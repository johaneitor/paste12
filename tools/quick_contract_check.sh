#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-${BASE:-}}"
if [ -z "${BASE}" ]; then
  echo "Uso: $0 BASE_URL" >&2; exit 1
fi

echo "== quick contract check =="
curl -sSI "$BASE" | sed -n 's/^cache-control:/cache-control:/Ip'
curl -sS "$BASE" | grep -iE 'p12-commit|p12-safe-shim|data-single' >/dev/null && echo "index flags: ok" || echo "index flags: missing"
for path in /terms /privacy; do
  code=$(curl -sS -o /dev/null -w '%{http_code}' "$BASE$path")
  echo "$path => $code"
done
curl -sS "$BASE/api/health" | jq -c . || true
curl -sS -X OPTIONS -D - -o /dev/null "$BASE/api/notes" | sed -n 's/^allow:/Allow:/Ip'
curl -sS -H 'Content-Type: application/json' -d '{"text":"hola"}' -D - -o /dev/null "$BASE/api/notes" | head -n1
curl -sS -d 'text=hola' -D - -o /dev/null "$BASE/api/notes" | head -n1
curl -sS "$BASE/api/notes?limit=10" -D - -o /dev/null | sed -n 's/^Link:/Link:/p'
