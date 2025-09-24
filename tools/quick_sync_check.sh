#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"
LOC="$(git rev-parse HEAD | head -c 40)"
REM="$(curl -fsS "$BASE/api/deploy-stamp" | sed -n 's/.*"commit": *"\([0-9a-f]\{7,40\}\)".*/\1/p')"
echo "Local : $LOC"
echo "Deploy: ${REM:-<n/a>}"
[ -n "${REM:-}" ] && [ "$LOC" = "$REM" ] && echo "✓ MATCH" || echo "✗ MISMATCH"
