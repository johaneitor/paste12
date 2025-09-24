#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
pick(){ for d in "/sdcard/Download" "/storage/emulated/0/Download" "$HOME/Download" "$HOME/downloads"; do [ -d "$d" ] && [ -w "$d" ] && { echo "$d"; return; }; done; echo "$HOME"; }
DEST="$(pick)"; TS="$(date -u +%Y%m%d-%H%M%SZ)"
B="$DEST/backend-audit-$TS.txt"
F="$DEST/frontend-audit-$TS.txt"
X="$DEST/fe-be-audit-$TS.txt"
tools/audit_backend_deep_v2.sh "$BASE" 2>&1 | tee "$B" >/dev/null || true
tools/audit_frontend_dump_v2.sh "$BASE"  2>&1 | tee "$F" >/dev/null || true
tools/trace_fe_be_v3.sh "$BASE"         2>&1 | tee "$X" >/dev/null || true
echo "OK: $B"; echo "OK: $F"; echo "OK: $X"
