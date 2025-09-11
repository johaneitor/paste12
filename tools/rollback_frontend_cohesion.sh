#!/usr/bin/env bash
set -euo pipefail
pick_index(){ for f in backend/static/index.html frontend/index.html index.html; do [ -f "$f" ] && { echo "$f"; return; }; done; echo "no index" >&2; exit 2; }
IDX="$(pick_index)"
BAK="${IDX}.cohesion.bak"

if [ -f "$BAK" ]; then
  cp -f "$BAK" "$IDX"
  echo "rollback: restaurado desde $(basename "$BAK")"
else
  # Si no hay .bak, borrar bloque por marcadores
  tmp="$(mktemp)"; awk 'BEGIN{p=1}/COHESION-SHIM START/{p=0}/COHESION-SHIM END/{p=1;next} p{print}' "$IDX" > "$tmp"
  mv "$tmp" "$IDX"
  echo "rollback: bloque de shim eliminado por marcadores"
fi
