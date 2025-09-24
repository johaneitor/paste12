#!/usr/bin/env bash
set -euo pipefail

# Ruta del proyecto
SRC="$HOME/paste12"
# Ruta de salida en la carpeta de descargas del celular
DST="/sdcard/Download/paste12_backup_$(date +%Y%m%d_%H%M%S).rar"

# Verifica que exista la carpeta de proyecto
[ -d "$SRC" ] || { echo "[!] No existe $SRC"; exit 1; }

# Comprimir en formato RAR
rar a -r "$DST" "$SRC"

echo "[ok] Backup creado en: $DST"
