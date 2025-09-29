#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE OUTDIR}"
OUTDIR="${2:?Uso: $0 BASE OUTDIR}"
echo "[1/3] Runtime…" >&2
tools/audit_runtime_health_v3.sh "$BASE" "$OUTDIR" | sed 's/^/  /' || true
echo "[2/3] Repo cleanliness…" >&2
tools/audit_repo_cleanliness_v3.sh "$OUTDIR" | sed 's/^/  /' || true
echo "[3/3] Code clones…" >&2
tools/audit_code_clones_run_v3.sh "$OUTDIR" | sed 's/^/  /' || true
echo "Artefactos en: $OUTDIR"
ls -1 "$OUTDIR" | sed 's/^/  /' || true
