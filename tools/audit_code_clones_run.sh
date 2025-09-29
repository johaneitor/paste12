#!/usr/bin/env bash
set -euo pipefail
TS="$(date -u +%Y%m%d-%H%M%SZ)"; OUT="${HOME}/Download/clones-$TS.txt"
python3 tools/audit_code_clones_v1.py "$OUT"
echo "Reporte de clones: $OUT"
