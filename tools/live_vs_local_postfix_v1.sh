#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR] }"
OUTDIR="${2:-/sdcard/Download}"

# 1) Ejecuta la v1 original para generar artefactos
tools/live_vs_local_v1.sh "$BASE" "$OUTDIR"

# 2) Ubicar prefijo del último paquete
prefix="$(ls -1t "$OUTDIR"/live-vs-local-*-index-remote.html | head -1)"
[[ -n "$prefix" ]] || { echo "ERROR: no encontré index-remote.html"; exit 1; }
base="${prefix%-index-remote.html}"
remote_html="${base}-index-remote.html"
local_html="${base}-index-local.html"
summary="${base}-summary.txt"
negfile="${base}-negative.txt"

# 3) Recalcular negativos con la suite correcta (404 esperados)
tools/negatives_assert_v1.sh "$BASE" | tee "$negfile" >/dev/null || true

# 4) Agregar comparación HTML ignorando el meta p12-commit
tools/html_compare_ignore_commit_v1.py "$remote_html" "$local_html" | tee -a "$summary"

echo "OK: live-vs-local post-fix listo → $(basename "$summary")"
