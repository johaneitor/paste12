#!/usr/bin/env bash
set -euo pipefail
edit() {
  f="$1"
  [ -f "$f" ] || return 0
  bak="${f}.bak_$(date -u +%Y%m%d-%H%M%SZ)"
  cp -f "$f" "$bak"
  # Inserta el meta name="p12-safe-shim" si no existe, justo después de <head>
  if ! grep -qi 'name="p12-safe-shim"' "$f"; then
    awk 'BEGIN{done=0} {print}
         /<head[^>]*>/ && !done { print "<meta name=\"p12-safe-shim\" content=\"1\">"; done=1 }' "$bak" > "$f"
    echo "OK: marcador safe-shim agregado en $f | backup=$(basename "$bak")"
  else
    echo "OK: marcador ya presente en $f"
  fi
}
edit backend/static/index.html
edit frontend/index.html
