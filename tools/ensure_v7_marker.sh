#!/usr/bin/env bash
set -euo pipefail
add_marker() {
  local f="$1"
  [ -f "$f" ] || return 0
  local bak="${f}.v7marker.bak"; [ -f "$bak" ] || cp -f "$f" "$bak"
  if grep -q 'id="p12-cohesion-v7"' "$f"; then
    echo "OK: v7 marker ya está en $f"; return 0
  fi
  awk 'BEGIN{added=0} /<\/head>/ && !added { print "<script id=\"p12-cohesion-v7\" type=\"application/json\">{\"v\":7}</script>"; added=1 } { print }' "$f" > "$f.tmp" && mv -f "$f.tmp" "$f"
  echo "✓ marcador v7 insertado en $f | backup=$(basename "$bak")"
}
add_marker backend/static/index.html || true
add_marker frontend/index.html || true
