#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"

echo "== REPO LOCAL =="
echo "cwd:     $(pwd)"
echo "topdir:  $(git rev-parse --show-toplevel 2>/dev/null || echo '<no-git>')"
local_sha="$(git rev-parse HEAD 2>/dev/null || echo '<no-git>')"
echo "HEAD:    ${local_sha}"

echo
echo "== DEPLOY REMOTO =="
remote_sha="$(curl -fsS "$BASE/api/deploy-stamp" | sed -n 's/.*"commit": *"\([0-9a-f]\{7,40\}\)".*/\1/p')"
echo "REMOTE:  ${remote_sha:-<sin valor>}"

if [[ -z "${remote_sha:-}" || "$local_sha" != "$remote_sha" ]]; then
  echo "=> MISMATCH (producción no está en tu HEAD local)"
else
  echo "=> OK (producción en tu HEAD)"
fi

echo
echo "== HEADERS / =="
curl -sI "$BASE/?_=$(date +%s)" | awk 'BEGIN{IGNORECASE=1}/^(HTTP\/|x-wsgi-bridge:|x-index-source:|cache-control:|server:|cf-cache-status:|age:)/{print}'

echo
echo "== PASTEL TOKEN en / =="
if curl -s "$BASE/?_=$(date +%s)" | grep -qm1 -- '--teal:#8fd3d0'; then
  echo "OK pastel"
else
  echo "NO pastel (token ausente)"
fi

echo
echo "== NO-STORE en / =="
if curl -sI "$BASE/?_=$(date +%s)" | awk 'BEGIN{IGNORECASE=1}/^cache-control:/{print}' | grep -qi 'no-store'; then
  echo "OK no-store"
else
  echo "NO no-store"
fi
