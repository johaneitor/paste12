#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL}"
LOCAL="$(git rev-parse HEAD)"
REMOTE="$(curl -fsSL "$BASE/api/deploy-stamp" 2>/dev/null | sed -n 's/.*"commit"[": ]*\([0-9a-f]\{7,40\}\).*/\1/p' || true)"
if [[ -z "${REMOTE:-}" ]]; then
  REMOTE="$(curl -fsSL "$BASE" 2>/dev/null | sed -n 's/.*name="p12-commit" content="\([0-9a-f]\{7,40\}\)".*/\1/p' || true)"
fi
echo "remote: ${REMOTE:-unknown}"
echo "local : $LOCAL"
[[ -n "${REMOTE:-}" && "$REMOTE" = "$LOCAL" ]]
