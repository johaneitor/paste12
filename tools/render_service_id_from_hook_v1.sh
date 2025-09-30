#!/usr/bin/env bash
set -euo pipefail
h="${RENDER_DEPLOY_HOOK:?export RENDER_DEPLOY_HOOK=...}"
echo "$h" | sed -n 's#.*deploy/\(srv-[a-z0-9]\+\)\?.*#\1#p'
