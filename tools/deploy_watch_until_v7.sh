#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE [timeout_s]}"
TIMEOUT="${2:-900}"
TARGET="$(git rev-parse HEAD)"
echo "Esperando a que remoto == $TARGET (timeout ${TIMEOUT}s)…"
t0="$(date +%s)"
probe(){
  rc="$(curl -fsS "$BASE/api/deploy-stamp" 2>/dev/null | sed -n 's/.*"commit"[": ]*\([0-9a-f]\{7,40\}\).*/\1/p')"
  if [[ -z "$rc" ]]; then
    rc="$(curl -fsS "$BASE" | sed -n 's/.*name="p12-commit" content="\([0-9a-f]\{7,40\}\)".*/\1/p')"
  fi
  [[ -n "$rc" ]] && echo "$rc" || echo "unknown"
}
while true; do
  remote="$(probe)"
  if [[ "$remote" == "$TARGET" ]]; then
    echo "OK: remoto == local ($remote)"
    exit 0
  fi
  if (( $(date +%s) - t0 > TIMEOUT )); then
    echo "ERROR: timeout (remote=$remote target=$TARGET)"
    exit 1
  fi
  sleep 5
done
