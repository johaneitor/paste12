#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
TAG="prod-${TS}"
HEAD="$(git rev-parse HEAD)"
MSG="paste12 release ${TS}
BASE : ${BASE}
HEAD : ${HEAD}
"
git tag -a "${TAG}" -m "${MSG}"
git push origin "${TAG}"
echo "OK: tag ${TAG} pushed"
