#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"
local_sha="$(git rev-parse HEAD | head -c 40)"
remote_sha="$(curl -fsS "$BASE/api/deploy-stamp" | sed -n 's/.*"commit": *"\([0-9a-f]\{7,40\}\)".*/\1/p')"

echo "Local:  $local_sha"
echo "Remote: ${remote_sha:-<sin valor>}"
if [[ -z "${remote_sha:-}" || "$local_sha" != "$remote_sha" ]]; then
  echo "=> MISMATCH (producción no está en tu HEAD)"
  exit 2
else
  echo "=> OK (producción en tu HEAD)"
fi

echo
echo "== HEADERS / =="
curl -sI "$BASE/" | awk 'BEGIN{IGNORECASE=1}/^(HTTP\/|x-wsgi-bridge:|x-index-source:|cache-control:|server:|cf-cache-status:)/{print}'

echo
echo "== PASTEL TOKEN en / =="
if curl -s "$BASE/" | grep -qm1 -- '--teal:#8fd3d0'; then
  echo "OK pastel"
else
  echo "NO pastel (token ausente)"
  exit 3
fi

echo
echo "== NO-STORE en / =="
if curl -sI "$BASE/" | awk 'BEGIN{IGNORECASE=1}/^cache-control:/{print}' | grep -qi 'no-store'; then
  echo "OK no-store"
else
  echo "NO no-store"
  exit 4
fi
