#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR] }"
OUTDIR="${2:-/sdcard/Download}"

echo "== patch BE =="
tools/patch_backend_create_notes_v1.sh

echo "== push =="
# seguridad: compilar otra vez antes de push
python -m py_compile wsgiapp/__init__.py && echo "py_compile OK"
git push -u origin main

echo "== redeploy + watch =="
# usa el pipeline que ya tenés configurado (API/hook + watch + auditorías básicas)
tools/redeploy_purge_watch_and_audit_v1.sh "$BASE" "$OUTDIR" || true

echo "== verify all behaviors =="
tools/verify_all_behaviors_v3.sh "$BASE" "$OUTDIR"

echo "Listo. Ver resumen en: $(ls -1dt "$OUTDIR"/p12-verify-* | head -1)/summary.tsv"
