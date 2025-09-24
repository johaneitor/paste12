#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; TIMEOUT="${2:-300}"; [ -n "$BASE" ] || { echo "uso: $0 https://host [timeout_s]"; exit 2; }
TARGET="$(git rev-parse origin/main)"
echo "Esperando que $BASE corra $TARGET (timeout ${TIMEOUT}s)..."
t0=$(date +%s)
while :; do
  REMOTE="$(curl -fsS "$BASE/api/deploy-stamp" | sed -n 's/.*"commit"[ ]*:[ ]*"\([0-9a-f]\{7,40\}\)".*/\1/p' | head -n1 || true)"
  if [ "$REMOTE" = "$TARGET" ]; then echo "✓ deploy en $REMOTE"; exit 0; fi
  now=$(date +%s); [ $((now - t0)) -ge "$TIMEOUT" ] && { echo "✗ timeout: remoto=$REMOTE, esperado=$TARGET"; exit 1; }
  sleep 5
done
