#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE [timeout_s]}"
TIMEOUT="${2:-480}"
TARGET="$(git rev-parse HEAD)"
echo "Esperando a que remoto == $TARGET (timeout ${TIMEOUT}s)…"
t0="$(date +%s)"
while true; do
  if tools/deploy_probe_v2.sh "$BASE" >/dev/null; then
    echo "OK: remoto == local"
    exit 0
  fi
  (( $(date +%s) - t0 > TIMEOUT )) && { echo "ERROR: timeout"; exit 1; }
  sleep 5
done
