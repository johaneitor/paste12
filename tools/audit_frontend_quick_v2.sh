#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }

pick_dest() {
  for d in "/sdcard/Download" "/storage/emulated/0/Download" "$HOME/storage/downloads" "$HOME/Download" "$HOME/downloads"; do
    if [ -d "$d" ] 2>/dev/null && [ -w "$d" ] 2>/dev/null; then echo "$d"; return; fi
  done
  mkdir -p "$HOME/downloads"; echo "$HOME/downloads"
}
DEST="$(pick_dest)"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
HTML="$DEST/index-$TS.html"
OUT="$DEST/frontend-audit-$TS.txt"

curl -fsS "$BASE/?_=$TS" -o "$HTML"
SCRIPTS="$(grep -oi '<script[^>]*>' "$HTML" | wc -l | tr -d ' ')"
HAS_V6="$(grep -qi 'P12 CONSOLIDATED HOTFIX v6' "$HTML" && echo 1 || echo 0)"
HAS_MORE="$(grep -qi 'Cargar más' "$HTML" && echo 1 || echo 0)"
HAS_SINGLE_META="$(grep -qi 'name="p12-single"' "$HTML" && echo 1 || echo 0)"
HAS_SINGLE_DATA="$(grep -qi 'data-single-note' "$HTML" && echo 1 || echo 0)"
KILL_BANNER="$(grep -qi 'deploy-stamp-banner' "$HTML" && echo 1 || echo 0)"

{
  echo "# Frontend Quick Audit — $TS"
  echo "- HTML guardado: $HTML"
  echo "- <script> tags: $SCRIPTS"
  echo "- Hotfix v6 presente: $HAS_V6"
  echo "- Botón 'Cargar más' en HTML: $HAS_MORE"
  echo "- Meta p12-single: $HAS_SINGLE_META | Data single-note: $HAS_SINGLE_DATA"
  echo "- Oculta banner de versión: $KILL_BANNER"
} > "$OUT"

echo "OK: resumen -> $OUT"
