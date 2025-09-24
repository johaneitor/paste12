#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?BASE faltante}"
REF="${2:-origin/main}"
remote="$(curl -fsS "$BASE/api/deploy-stamp" | sed -n 's/.*"commit"[[:space:]]*:[[:space:]]*"\([0-9a-f]\{7,40\}\)".*/\1/p' | head -1)"
local="$(git rev-parse "$REF")"
printf 'remote: %s\n%s: %s\n' "$remote" "$REF" "$local" >&2
[[ "$remote" == "$local" ]]
