#!/usr/bin/env bash
set -euo pipefail

F="render_entry.py"
[ -f "$F" ] || { echo "[!] No existe $F"; exit 1; }

BKP="$F.bak.$(date +%Y%m%d-%H%M%S)"
cp -a "$F" "$BKP"
echo "[i] Backup en $BKP"

# 1) Deduplicar líneas consecutivas en las primeras 120 líneas (típico origen del try/try duplicado)
TMP="$(mktemp)"
{
  head -n 120 "$F" | awk '
    BEGIN{prev=""}
    { if($0==prev) next; print; prev=$0 }
  '
  tail -n +121 "$F"
} > "$TMP"
mv "$TMP" "$F"
echo "[ok] Header (1..120) deduplicado (líneas consecutivas idénticas)"

# 2) Dedupe específico ya aplicado (por si reaparece)
sed -i 's/^from __future__ import annotations$//;t; s/^import os, hashlib$//;t' "$F" || true

# 3) Compilar
echo "[1] py_compile…"
python -m py_compile "$F" && echo "[ok] Compilación OK"

# 4) Smoke local rápido (sin romper si ya lo tienes)
if [ -x tools/static_smoke_render_entry.sh ]; then
  echo "[2] Smoke local"
  tools/static_smoke_render_entry.sh || true
fi

# 5) Probe remoto (no falla el script si hay 404, solo muestra)
if [ -x tools/remote_probe_ix.sh ]; then
  echo "[3] Probe remoto"
  tools/remote_probe_ix.sh || true
fi

echo "[✓] Listo."
