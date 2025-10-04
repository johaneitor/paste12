#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR]}"
OUTDIR="${2:-/sdcard/Download}"
mkdir -p "$OUTDIR"

echo "== verify: POS/NEG/LIMITS =="
tools/verify_all_behaviors_v4.sh "$BASE" "$OUTDIR" || true

echo "== runtime pack5 (sin redeploy) =="
tools/run_pack5_no_redeploy_v2.sh "$BASE" "$OUTDIR" || true

echo "OK. Artefactos en $OUTDIR"
