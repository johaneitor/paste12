#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?BASE faltante}"
SECS="${2:-480}"
deadline=$(( $(date +%s) + SECS ))
local="$(git rev-parse HEAD)"
echo "Esperando a que remoto == $local (timeout ${SECS}s)…"
while :; do
  remote="$(curl -fsS "$BASE/api/deploy-stamp" | sed -n 's/.*"commit"[[:space:]]*:[[:space:]]*"\([0-9a-f]\{7,40\}\)".*/\1/p' | head -1)"
  printf 'now remote=%s\n' "$remote"
  [[ "$remote" == "$local" ]] && { echo "OK: deploy sincronizado."; exit 0; }
  [[ $(date +%s) -ge $deadline ]] && { echo "Timeout esperando deploy"; exit 1; }
  sleep 6
done
