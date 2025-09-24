#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
local_sha="$(git rev-parse HEAD)"
remote_sha="$(curl -fsS "$BASE/api/deploy-stamp" | sed -n 's/.*"commit":"\([0-9a-f]\{40\}\)".*/\1/p')"
echo "remote: ${remote_sha:-<desconocido>}"
echo "  local: $local_sha"
if [ "$remote_sha" != "$local_sha" ]; then
  echo "✗ mismatch (remote != local)"; exit 3
fi
echo "✓ remoto sincronizado con HEAD"
