#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?BASE faltante}"
REF="${2:-origin/main}"
SECS="${3:-480}"
deadline=$(( $(date +%s) + SECS ))
goal="$(git rev-parse "$REF")"
echo "Esperando a que remoto == $REF ($goal) (timeout ${SECS}s)…"
while :; do
  remote="$(curl -fsS "$BASE/api/deploy-stamp" | sed -n 's/.*"commit"[[:space:]]*:[[:space:]]*"\([0-9a-f]\{7,40\}\)".*/\1/p' | head -1)"
  printf 'now remote=%s\n' "$remote"
  [[ "$remote" == "$goal" ]] && { echo "OK: deploy sincronizado con $REF."; exit 0; }
  [[ $(date +%s) -ge $deadline ]] && { echo "Timeout esperando deploy"; exit 1; }
  sleep 6
done
