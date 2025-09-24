#!/usr/bin/env bash
set -euo pipefail

ARCH="frontend/.archive_$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p "$ARCH"

move_if(){
  local f="$1"
  [[ -f "$f" ]] && { mv -f "$f" "$ARCH/"; echo "archivado: $f"; }
}

# patrones comunes de residuos
for f in frontend/index.*.bak frontend/*.old.html frontend/*-legacy*.html frontend/legacy*; do
  for x in $f; do
    [[ -e "$x" ]] && move_if "$x"
  done
done

echo "OK: limpieza (archivado en $ARCH)"
