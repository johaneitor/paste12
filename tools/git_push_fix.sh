#!/usr/bin/env bash
set -euo pipefail

MSG="${1:-fix: update render_entry and tools}"

echo "[i] Haciendo backup rápido de render_entry.py"
cp -a render_entry.py "render_entry.py.bak.$(date +%Y%m%d-%H%M%S)"

echo "[i] Añadiendo cambios…"
git add render_entry.py tools/

echo "[i] Commit con mensaje: $MSG"
git commit -m "$MSG" || { echo "[!] Nada para commitear"; exit 0; }

echo "[i] Push a GitHub remoto: johaneitor/paste12.git"
git push https://github.com/johaneitor/paste12.git HEAD:main
