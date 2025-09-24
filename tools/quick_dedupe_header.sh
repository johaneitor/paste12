#!/usr/bin/env bash
set -euo pipefail
F="render_entry.py"
[ -f "$F" ] || { echo "[!] No existe $F"; exit 1; }
BKP="$F.bak.$(date +%Y%m%d-%H%M%S)"
cp -a "$F" "$BKP"
echo "[i] Backup en $BKP"
# elimina duplicados en cabecera
sed -i 's/^from __future__ import annotations$//;t; s/^import os, hashlib$//;t' "$F"
echo "[ok] Cabecera deduplicada"
