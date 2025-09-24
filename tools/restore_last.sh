#!/usr/bin/env bash
set -euo pipefail
F="${1:?Uso: $0 ruta/al/archivo}"
DIR="tools/backups/$(dirname "$F")"
BASE="$(basename "$F")"
LAST=$(ls -1t "$DIR/$BASE".*.bak 2>/dev/null | head -n1 || true)
[ -z "$LAST" ] && { echo "No hay backups para $F"; exit 1; }
cp -a "$LAST" "$F"
echo "Restaurado desde: $LAST -> $F"
