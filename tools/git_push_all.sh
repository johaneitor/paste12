#!/usr/bin/env bash
set -euo pipefail

# Mensaje opcional
MSG="${1:-chore: push tools scripts + render_entry.py}"

echo "[i] Backup rápido de render_entry.py (si existe)…"
[ -f render_entry.py ] && cp -a render_entry.py "render_entry.py.bak.$(date +%Y%m%d-%H%M%S)" || true

echo "[i] Añadiendo cambios…"
git add -A
git status --short

echo "[i] Commit: $MSG"
git commit -m "$MSG" || { echo "[!] Nada para commitear"; exit 0; }

# Empuja a tu remoto de GitHub (como pediste con URL explícita)
echo "[i] Push a GitHub: johaneitor/paste12.git (branch main)"
git push https://github.com/johaneitor/paste12.git HEAD:main
