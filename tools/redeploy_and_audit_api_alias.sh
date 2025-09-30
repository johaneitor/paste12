#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR]}"; OUTDIR="${2:-/sdcard/Download}"
tools/redeploy_via_api_and_watch_v4.sh "$BASE" "$OUTDIR"
