#!/usr/bin/env bash
set -euo pipefail
HTML="${1:-frontend/index.html}"
ADSENSE="${2:-${ADSENSE_ID:-}}"
BASE="${3:-https://paste12-rmsk.onrender.com}"
OUT="${4:-/sdcard/Download}"

tools/frontend_reconcile_v4.sh "$HTML" "${ADSENSE:-}"
tools/audit_frontend_extensive_v4.sh "$BASE" "$OUT"
