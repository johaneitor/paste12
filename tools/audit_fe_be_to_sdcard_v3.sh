#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE}"
HERE="$(cd "$(dirname "$0")" && pwd)"
"$HERE/audit_frontend_to_sdcard_v3.sh" "$BASE" >/dev/null
"$HERE/audit_backend_to_sdcard_v3.sh" "$BASE" >/dev/null
OUT="${HOME}/Download"
ls -1 "$OUT"/*"$(date -u +%Y%m%d)"* | sed -n '1,20p' || true
