#!/usr/bin/env bash
set -euo pipefail

F="render_entry.py"
[ -f "$F" ] || { echo "[!] No existe $F"; exit 1; }

BKP="render_entry.py.bak.$(date +%Y%m%d-%H%M%S)"
cp -a "$F" "$BKP"

# Corrige indentación de class Note si quedó mal
sed -i 's/^[[:space:]]\{1,\}class Note/class Note/' "$F"

python -m py_compile "$F"
echo "[✓] Compilación OK"
echo "[i] Backup en: $BKP"
