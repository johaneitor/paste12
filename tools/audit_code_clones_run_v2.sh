#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUTDIR="$("$HERE/_resolve_outdir.sh")"; mkdir -p "$OUTDIR"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
OUT="$OUTDIR/clones-$TS.txt"
python3 "$HERE/audit_code_clones_v2.py" "$OUT"
echo "Reporte de clones: $OUT"
