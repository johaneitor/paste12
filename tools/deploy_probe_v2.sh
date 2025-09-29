#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL}"
LOCAL="$(git rev-parse HEAD)"
REMOTE="$(curl -fsSL "$BASE/api/deploy-stamp" 2>/dev/null | sed -n 's/.*"commit"[": ]*\([0-9a-f]\{7,40\}\).*/\1/p' || true)"
[[ -z "${REMOTE:-}" ]] && REMOTE="$(curl -fsSL "$BASE" 2>/dev/null | sed -n 's/.*name="p12-commit" content="\([0-9a-f]\{7,40\}\)".*/\1/p' || true)"
echo "remote: ${REMOTE:-unknown}"
echo "local : $LOCAL"
[[ -n "${REMOTE:-}" && "$REMOTE" = "$LOCAL" ]]
