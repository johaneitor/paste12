#!/usr/bin/env bash
set -euo pipefail
files=()
[ -f backend/static/index.html ] && files+=(backend/static/index.html)
[ -f frontend/index.html ]       && files+=(frontend/index.html)
[ ${#files[@]} -eq 0 ] && { echo "✗ no hay index.html para marcar"; exit 0; }

inject_one() {
  local f="$1"
  local bak="${f}.v7marker.bak"
  [ -f "$bak" ] || cp -f "$f" "$bak"

  if grep -q 'name="p12-cohesion"' "$f"; then
    echo "OK: $f ya tiene marcador v7"
  else
    # Insertar meta + script nosw antes de </head> (o al final si no hay head)
    if grep -qi '</head>' "$f"; then
      awk '
        BEGIN{IGNORECASE=1}
        /<\/head>/ && !done {
          print "  <!-- p12:cohesion v7 -->"
          print "  <meta name=\"p12-cohesion\" content=\"v7\">"
          print "  <script id=\"p12-nosw\" data-nosw>if(location.search.includes(\"nosw=1\")&&\"serviceWorker\" in navigator){navigator.serviceWorker.getRegistrations().then(rs=>rs.forEach(r=>r.unregister())).catch(()=>{});}</script>"
          done=1
        }
        {print}
      ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
      echo "• inyectado marcador v7 en $f (backup=$(basename "$bak"))"
    else
      printf '%s\n' \
        '<!-- p12:cohesion v7 -->' \
        '<meta name="p12-cohesion" content="v7">' \
        '<script id="p12-nosw" data-nosw>if(location.search.includes("nosw=1")&&"serviceWorker" in navigator){navigator.serviceWorker.getRegistrations().then(rs=>rs.forEach(r=>r.unregister())).catch(()=>{});}</script>' \
        >> "$f"
      echo "• agregado marcador v7 al final (sin </head>) en $f (backup=$(basename "$bak"))"
    fi
  fi
}

for f in "${files[@]}"; do inject_one "$f"; done
