#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR] }"
OUTDIR="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
DEST="${OUTDIR}/p12-prod-${TS}"
mkdir -p "$DEST"

echo "== verify_all_green =="
tools/verify_all_green_v1.sh "$BASE" "$OUTDIR" || true

echo "== runtime GET smoke =="
tools/runtime_smoke_get_v1.sh "$BASE" "$OUTDIR" || true

# Recolecta últimos artefactos conocidos
copy_last() { # $1: glob, $2: rename
  f="$(ls -1t $1 2>/dev/null | head -1 || true)"
  [[ -n "${f}" ]] && cp -f "${f}" "${DEST}/$2"
}

copy_last "${OUTDIR}/live-vs-local-*summary.txt" "live-vs-local-summary.txt"
copy_last "${OUTDIR}/runtime-*.txt"              "runtime-latest.txt"
copy_last "${OUTDIR}/fe-flags-*/index-remote.html" "index-remote.html"
copy_last "${OUTDIR}/runtime-smoke-get-*/summary.tsv" "runtime-smoke-get.tsv"

# Guardar commit remoto desde el index (fallback si /api/deploy-stamp no existe)
REMOTE_COMMIT="$(curl -fsS "$BASE/api/deploy-stamp" 2>/dev/null | sed -n 's/.*"commit"[": ]*\([0-9a-f]\{7,40\}\).*/\1/p')"
if [[ -z "$REMOTE_COMMIT" ]]; then
  REMOTE_COMMIT="$(curl -fsS "$BASE" | sed -n 's/.*name="p12-commit" content="\([0-9a-f]\{7,40\}\)".*/\1/p')"
fi
LOCAL_HEAD="$(git rev-parse HEAD)"

{
  echo "== paste12 release =="
  echo "ts_utc: ${TS}"
  echo "base  : ${BASE}"
  echo "head  : ${LOCAL_HEAD}"
  echo "remote: ${REMOTE_COMMIT:-unknown}"
  echo
  echo "Artefactos:"
  ls -1 "${DEST}" || true
} | tee "${DEST}/SUMMARY.txt"

echo "OK. Paquete final en: ${DEST}"
