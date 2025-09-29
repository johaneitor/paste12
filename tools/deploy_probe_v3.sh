#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL}"
LOCAL="$(git rev-parse HEAD)"

get_commit_from_index(){
  url="$1"
  curl -fsSL "$url" 2>/dev/null | sed -n 's/.*name="p12-commit" content="\([0-9a-f]\{7,40\}\)".*/\1/p' | head -n1
}

# 1) Preferir /api/deploy-stamp si existe
REMOTE="$(curl -fsSL "$BASE/api/deploy-stamp" 2>/dev/null | sed -n 's/.*"commit"[": ]*\([0-9a-f]\{7,40\}\).*/\1/p' || true)"

# 2) Fallback: parsear commit del /
if [[ -z "${REMOTE:-}" ]]; then
  REMOTE="$(get_commit_from_index "$BASE")"
fi
# 3) Fallback adicional: /index.html (algunos setups sirven el index allí)
if [[ -z "${REMOTE:-}" ]]; then
  REMOTE="$(get_commit_from_index "$BASE/index.html")"
fi

echo "remote: ${REMOTE:-unknown}"
echo "local : $LOCAL"
[[ -n "${REMOTE:-}" && "$REMOTE" = "$LOCAL" ]]
