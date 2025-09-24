#!/usr/bin/env bash
set -euo pipefail

F="${1:-render_entry.py}"
START="${2:-1}"
COUNT="${3:-40}"

[ -f "$F" ] || { echo "[!] No existe $F"; exit 1; }

END=$((START + COUNT - 1))
echo "[i] Mostrando $F líneas $START-$END"
nl -ba "$F" | sed -n "${START},${END}p"
