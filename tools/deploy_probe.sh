#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
remote="$(curl -fsS "$BASE/api/deploy-stamp" | sed -n 's/.*"commit"[[:space:]]*:[[:space:]]*"\([0-9a-f]\{7,40\}\)".*/\1/p' | head -1)"
local="$(git rev-parse HEAD)"
printf 'remote: %s\nlocal:  %s\n' "$remote" "$local" >&2
[[ "$remote" == "$local" ]]
