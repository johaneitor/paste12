#!/usr/bin/env bash
set -euo pipefail

SRC="$HOME/paste12"
DST="/sdcard/Download/paste12_backup_$(date +%Y%m%d_%H%M%S).zip"

[ -d "$SRC" ] || { echo "[!] No existe $SRC"; exit 1; }

zip -r "$DST" "$SRC"

echo "[ok] Backup creado en: $DST"
