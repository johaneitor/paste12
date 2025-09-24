#!/usr/bin/env bash
set -euo pipefail
F="${1:?Uso: $0 ruta/al/archivo}"
TS=$(date +%Y%m%d_%H%M%S)
DIR="tools/backups/$(dirname "$F")"
mkdir -p "$DIR"
DEST="$DIR/$(basename "$F").$TS.bak"
cp -a "$F" "$DEST"
echo "Backup creado: $DEST"
