#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR] }"
OUTDIR="${2:-/sdcard/Download}"

tools/live_vs_local_v1.sh "$BASE" "$OUTDIR"

# Localizar el último paquete generado
prefix="$(ls -1t "$OUTDIR"/live-vs-local-*-index-remote.html | head -1)"
[[ -n "$prefix" ]] || { echo "ERROR: no encontré index-remote.html"; exit 2; }
base="${prefix%-index-remote.html}"
remote_html="${base}-index-remote.html"
local_html="${base}-index-local.html"
summary="${base}-summary.txt"
negfile="${base}-negative.txt"

# Recalcular negativos usando la suite correcta (404 esperados)
tools/negatives_assert_v1.sh "$BASE" | tee "$negfile" >/dev/null || true

# Comparación normalizada (ignora meta p12-commit y colapsa whitespace)
tools/html_compare_ignore_commit_v1.py "$remote_html" "$local_html" | tee -a "$summary"

echo "OK: v2 listo → $(basename "$summary")"
