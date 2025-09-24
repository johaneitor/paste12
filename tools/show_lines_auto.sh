#!/usr/bin/env bash
set -euo pipefail

F="${1:-render_entry.py}"
HEAD_START="${2:-1}"
HEAD_COUNT="${3:-40}"

[ -f "$F" ] || { echo "[!] No existe $F"; exit 1; }

echo "[i] Mostrando $F líneas ${HEAD_START}-$((HEAD_START+HEAD_COUNT-1))"
nl -ba "$F" | sed -n "${HEAD_START},$((HEAD_START+HEAD_COUNT-1))p"

echo "[i] Mostrando $F líneas 90-129"
nl -ba "$F" | sed -n '90,129p'
