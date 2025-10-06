#!/usr/bin/env bash
# Uso: tools/p12_status_now_v2.sh BASE_URL
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
TMP="${HOME}/tmp/p12-status-${TS}"
mkdir -p "$TMP"; trap 'rm -rf "$TMP"' EXIT
echo "== p12 STATUS @ ${TS} =="
echo "BASE: $BASE"
echo
echo "-- Deploy probe --"
REMOTE="$(curl -fsS "$BASE/api/deploy-stamp" 2>/dev/null | sed -n 's/.*"commit"[": ]*\([0-9a-f]\{7,40\}\).*/\1/p' || true)"
if [ -z "$REMOTE" ]; then
  curl -fsS "$BASE" -o "$TMP/idx.html" -D "$TMP/h.txt" || true
  REMOTE="$(sed -n 's/.*name="p12-commit" content="\([0-9a-f]\{7,40\}\)".*/\1/ip' "$TMP/idx.html" | head -n1)"
fi
LOCAL="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
echo "remote: ${REMOTE:-unknown}"
echo "local : ${LOCAL}"
[ -n "${REMOTE:-}" ] && [ "$REMOTE" = "$LOCAL" ] && echo "drift: aligned" || echo "drift: DRIFT/unknown"
echo
echo "-- POSITIVOS --"
for p in "/" "/terms" "/privacy"; do
  code="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE$p" || true)"
  printf "GET %-8s → %s\n" "$p" "$code"
done
echo
echo "-- API --"
echo "preflight /api/notes (Allow):"
curl -fsS -X OPTIONS -D - -o /dev/null "$BASE/api/notes" 2>/dev/null | sed -n 's/^allow:/Allow:/Ip' || true
echo "list /api/notes?limit=10:"
curl -sS -o /dev/null -w 'code:%{http_code}\n' "$BASE/api/notes?limit=10"
