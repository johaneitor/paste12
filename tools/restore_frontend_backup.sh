#!/usr/bin/env bash
set -euo pipefail
target="${1:-auto}" # "auto" o ruta a backup .bak
restore_one() {
  local orig="$1" sub f d b
  [ -f "$orig" ] || return 0
  d="$(dirname "$orig")"; b="$(basename "$orig")"
  if [ "$target" = "auto" ]; then
    # elige el backup más reciente con tamaño > 0
    f="$(find "$d" -maxdepth 1 \( -name "${b}.bak" -o -name "${b}.*.bak" -o -name "${b}.*.p12*.bak" -o -name "${b}.pre_v7*.bak" \) -type f -printf "%T@ %p\n" \
        | sort -nr | awk '{$1=""; sub(/^ /,""); print}' \
        | while read -r p; do [ -s "$p" ] && echo "$p" && break; done)"
  else
    f="$target"
  fi
  [ -n "${f:-}" ] && [ -f "$f" ] || { echo "✗ no encontré backup para $orig"; return 0; }
  local saf="${orig}.restore_bak.$(date -u +%Y%m%d-%H%M%SZ)"
  cp -f "$orig" "$saf" 2>/dev/null || true
  cp -f "$f" "$orig"
  echo "Restaurado $orig <- $f | copia de seguridad: $(basename "$saf")"
}
restore_one backend/static/index.html
restore_one frontend/index.html
