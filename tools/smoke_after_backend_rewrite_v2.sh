#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://TU_HOST}"
echo "== Smoke ${BASE} =="
echo "-- /api/health --"
curl -fsS "$BASE/api/health" || true
echo; echo "-- OPTIONS /api/notes --"
curl -fsSi -X OPTIONS "$BASE/api/notes" | sed -n '1,20p'
echo "-- GET /api/notes (headers) --"
curl -fsSi "$BASE/api/notes?limit=5" | sed -n '1,20p' || true
