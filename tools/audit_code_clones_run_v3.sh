#!/usr/bin/env bash
set -euo pipefail
OUTDIR="${1:-}"
if [[ -z "$OUTDIR" ]]; then
  for d in "$HOME/storage/downloads" "/sdcard/Download" "/storage/emulated/0/Download" "$HOME/Download"; do
    [[ -d "$d" && -w "$d" ]] && OUTDIR="$d" && break
  done
fi
mkdir -p "$OUTDIR"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
OUT="$OUTDIR/clones-$TS.txt"
python3 tools/audit_code_clones_v3.py "$OUT"
echo "Reporte de clones: $OUT"
