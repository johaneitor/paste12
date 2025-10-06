#!/usr/bin/env bash
# Uso: tools/p12_status_now_v3.sh BASE_URL
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
TMP="${HOME}/tmp/p12-status-${TS}"
mkdir -p "$TMP"; trap 'rm -rf "$TMP"' EXIT

echo "== p12 STATUS @ ${TS} =="
echo "BASE: $BASE"
echo
echo "-- Deploy probe --"

REMOTE="$(curl -sS "$BASE/api/deploy-stamp" 2>/dev/null \
  | sed -n 's/.*"commit"[": ]*\([0-9a-f]\{7,40\}\).*/\1/p' || true)"

# Intento de index (aunque / sea 404, lo manejamos)
CODE_ROOT="$(curl -sS -o "$TMP/idx.html" -w '%{http_code}' "$BASE" || echo 000)"
[ "$CODE_ROOT" -ge 200 ] && [ "$CODE_ROOT" -lt 300 ] || rm -f "$TMP/idx.html"

if [ -z "$REMOTE" ] && [ -f "$TMP/idx.html" ]; then
  REMOTE="$(sed -n 's/.*name="p12-commit" content="\([0-9a-f]\{7,40\}\)".*/\1/ip' "$TMP/idx.html" | head -n1)"
fi

LOCAL="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
echo "remote: ${REMOTE:-unknown}"
echo "local : ${LOCAL}"
if [ -n "${REMOTE:-}" ] && [ "$REMOTE" = "$LOCAL" ]; then
  echo "drift: aligned"
else
  echo "drift: DRIFT/unknown"
fi

echo
echo "-- POSITIVOS --"
for p in "/" "/terms" "/privacy"; do
  code="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE$p" || echo 000)"
  printf "GET %-8s → %s\n" "$p" "$code"
done

echo
echo "-- API --"
echo "preflight /api/notes (Allow):"
curl -sS -X OPTIONS -D - -o /dev/null "$BASE/api/notes" 2>/dev/null | sed -n 's/^allow:/Allow:/Ip' || true
echo "list /api/notes?limit=10:"
curl -sS -o /dev/null -w 'code:%{http_code}\n' "$BASE/api/notes?limit=10" || true
