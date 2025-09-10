#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }

echo "== /api/deploy-stamp =="
curl -sS -i "$BASE/api/deploy-stamp" | sed -n '1,80p'

echo "== Parseo =="
BODY="$(curl -fsS "$BASE/api/deploy-stamp" || true)"
if [ -z "$BODY" ]; then echo "✗ sin body"; exit 1; fi
COMMIT="$(jq -r '.deploy.commit // .commit // empty' <<<"$BODY" 2>/dev/null || true)"
DATE="$(jq -r '.deploy.date // .date // empty'   <<<"$BODY" 2>/dev/null || true)"
echo "commit=${COMMIT:-<vacío>} date=${DATE:-<vacío>}"

echo "== index.html (primeras líneas) =="
curl -sS "$BASE/" | sed -n '1,80p' || true
