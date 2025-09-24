#!/usr/bin/env bash
set -euo pipefail

F="render_entry.py"
[ -f "$F" ] || { echo "[!] No existe $F"; exit 1; }

echo "[1] py_compile…"
python -m py_compile "$F" && echo "[✓] OK"

echo "[2] Cabecera 1–60"
nl -ba "$F" | sed -n '1,60p'

echo "[3] Bloque notas 90–160"
nl -ba "$F" | sed -n '90,160p'
