#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/env_load.sh"
TS="$(date -u +%Y%m%d-%H%M%SZ)"; OUT="${HOME}/Download"; mkdir -p "$OUT"

echo "[1/4] Runtime…" >&2
"$HERE/audit_runtime_health_v1.sh" | sed 's/^/  /' || true

echo "[2/4] Repo cleanliness…" >&2
"$HERE/audit_repo_cleanliness_v1.sh" | sed 's/^/  /' || true

echo "[3/4] Code clones…" >&2
"$HERE/audit_code_clones_run.sh" | sed 's/^/  /' || true

echo "[4/4] Resumen artefactos:" >&2
ls -1 "$OUT"/*"$TS"* 2>/dev/null | sed 's/^/  /' || echo "  (nada con TS exacto; ver archivos recientes en $OUT)"
