#!/usr/bin/env bash
set -euo pipefail
SRC="${HOME}/Download"
# candidatos en Android
candidates=( "${HOME}/storage/downloads" "/sdcard/Download" "/storage/emulated/0/Download" )
DEST=""
for d in "${candidates[@]}"; do
  if [[ -d "$d" && -w "$d" ]]; then DEST="$d"; break; fi
done
if [[ -z "$DEST" ]]; then
  echo "No encuentro carpeta compartida (sdcard). Corré una vez: termux-setup-storage" >&2
  exit 2
fi
TS="$(date -u +%Y%m%d-%H%M%SZ)"
DEST_DIR="$DEST/paste12-audits"
mkdir -p "$DEST_DIR"

shopt -s nullglob
files=( "$SRC"/runtime-*.txt "$SRC"/repo-audit-*.txt "$SRC"/clones-*.txt \
        "$SRC"/index-*.html "$SRC"/api-notes-*.json "$SRC"/options-*.txt \
        "$SRC"/health-*.json "$SRC"/terms-*.html "$SRC"/privacy-*.html \
        "$SRC"/deploy-stamp-*.json )
copied=0
for f in "${files[@]}"; do
  base="$(basename "$f")"
  # si ya existe, versionamos con timestamp
  if [[ -e "$DEST_DIR/$base" ]]; then
    ext="${base##*.}"; name="${base%.*}"
    cp -f "$f" "$DEST_DIR/${name}-$TS.$ext"
  else
    cp -f "$f" "$DEST_DIR/"
  fi
  copied=$((copied+1))
done

echo "Copiados $copied archivos a: $DEST_DIR"
if ((copied==0)); then
  echo "No había artefactos en ${SRC}. Corré antes las auditorías (tools/audit_full_stack_v1.sh)." >&2
fi
ls -1 "$DEST_DIR" | sed 's/^/  /' || true
