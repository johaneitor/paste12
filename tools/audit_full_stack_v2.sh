#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUTDIR="$("$HERE/_resolve_outdir.sh")"; mkdir -p "$OUTDIR"
TS="$(date -u +%Y%m%d-%H%M%SZ)"

echo "[1/4] Runtime…" >&2
"$HERE/audit_runtime_health_v2.sh" | sed 's/^/  /' || true

echo "[2/4] Repo cleanliness…" >&2
"$HERE/audit_repo_cleanliness_v2.sh" | sed 's/^/  /' || true

echo "[3/4] Code clones…" >&2
"$HERE/audit_code_clones_run_v2.sh" | sed 's/^/  /' || true

echo "[4/4] Resumen artefactos en $OUTDIR :" >&2
ls -1 "$OUTDIR"/*"$TS"* 2>/dev/null | sed 's/^/  /' || echo "  (si no ves archivos con TS exacto, igual están en $OUTDIR)"
# Aviso si OUTDIR no es sdcard
case "$OUTDIR" in
  *storage/downloads*|*/sdcard/Download/*|*/emulated/0/Download/*) : ;;
  *) echo "NOTE: OUTDIR=$OUTDIR no es sdcard. Corré 'termux-setup-storage'." >&2 ;;
esac
