#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; TIMEOUT="${2:-480}"
[ -n "$BASE" ] || { echo "uso: $0 https://host [timeout_s]"; exit 2; }
want="$(git rev-parse HEAD)"
echo "Esperando que $BASE corra $want (timeout ${TIMEOUT}s)..."
t0=$(date +%s)
while :; do
  now=$(date +%s); (( now - t0 > TIMEOUT )) && { echo "✗ timeout"; exit 1; }
  got="$(curl -fsS "$BASE/api/deploy-stamp" | sed -n 's/.*"commit":"\([0-9a-f]\{40\}\)".*/\1/p')"
  if [ -n "$got" ]; then
    if [ "$got" = "$want" ]; then echo "✓ remoto=$got"; exit 0; fi
    echo "… remoto=$got, esperando $want"
  else
    echo "… no pude leer /api/deploy-stamp"
  fi
  sleep 6
done
