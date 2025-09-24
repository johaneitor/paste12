#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"

git fetch origin --tags --prune >/dev/null 2>&1 || true

LOCAL="$(git rev-parse HEAD | head -c 40 2>/dev/null || true)"
ORIGIN="$(git rev-parse origin/main | head -c 40 2>/dev/null || true)"
DEPLOY="$(curl -fsS "$BASE/api/deploy-stamp" | sed -n 's/.*"commit": *"\([0-9a-f]\{7,40\}\)".*/\1/p')"

echo "Local : ${LOCAL:-<n/a>}"
echo "Origin: ${ORIGIN:-<n/a>}"
echo "Deploy: ${DEPLOY:-<sin valor>}"

if [[ -n "$LOCAL" && -n "$ORIGIN" ]]; then
  if [[ "$LOCAL" == "$ORIGIN" ]]; then echo "· OK: local == origin"; else echo "· MISMATCH: local != origin"; fi
fi

if [[ -n "$ORIGIN" && -n "$DEPLOY" ]]; then
  if [[ "$ORIGIN" == "$DEPLOY" ]]; then echo "· OK: origin == deploy"; else echo "· MISMATCH: origin != deploy"; fi
fi

if [[ -n "$LOCAL" && -n "$DEPLOY" ]]; then
  if [[ "$LOCAL" == "$DEPLOY" ]]; then echo "· OK: local == deploy"; else echo "· MISMATCH: local != deploy"; fi
fi
