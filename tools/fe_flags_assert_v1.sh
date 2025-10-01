#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL}"
OUT="${2:-$HOME/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
DEST="${OUT}/fe-flags-${TS}"
mkdir -p "$DEST"
curl -fsS "$BASE" -o "${DEST}/index-remote.html"
ok=1
grep -qi 'name="p12-commit"' "${DEST}/index-remote.html" && echo "OK p12-commit" || { echo "FAIL p12-commit"; ok=0; }
grep -qi 'p12-safe-shim'      "${DEST}/index-remote.html" && echo "OK p12-safe-shim" || { echo "FAIL p12-safe-shim"; ok=0; }
grep -qi 'data-single="1"'    "${DEST}/index-remote.html" && echo "OK data-single=1" || { echo "FAIL data-single=1"; ok=0; }
echo "HTML guardado en ${DEST}/index-remote.html"
[[ $ok -eq 1 ]] && echo "FE_FLAGS_OK" || { echo "FE_FLAGS_FAIL"; exit 1; }
