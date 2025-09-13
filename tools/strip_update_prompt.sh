#!/usr/bin/env bash
set -euo pipefail
for f in backend/static/index.html frontend/index.html; do
  [ -f "$f" ] || continue
  bak="${f}.bak_prompt_$(date -u +%Y%m%d-%H%M%SZ)"
  cp -f "$f" "$bak"
  # Elimina bloques tipo <div id="update-prompt">...</div> y script con texto 'actualización disponible'
  sed -E -e '/id="update-prompt"/,/<\/div>/d' \
         -e '/actualizaci[oó]n disponible/Id' "$bak" > "$f"
  echo "OK: prompt eliminado si existía en $f | backup=$(basename "$bak")"
done
