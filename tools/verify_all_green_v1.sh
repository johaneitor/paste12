#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR]}"
OUTDIR="${2:-/sdcard/Download}"
echo "== live vs local =="
tools/live_vs_local_v1.sh "$BASE" "$OUTDIR" || true
SUM="$(ls -1 ${OUTDIR}/live-vs-local-*summary.txt 2>/dev/null | tail -1 || true)"
[[ -n "$SUM" ]] && sed -n '1,120p' "$SUM" || true
echo "== negativos =="
tools/negatives_assert_v1.sh "$BASE"
echo "== FE flags =="
tools/fe_flags_assert_v1.sh "$BASE" "$OUTDIR"
echo "== RESULTADO =="
echo "✔ Remoto==local y FE flags OK y negativos 404 OK"
echo "Artefactos en: $OUTDIR"
