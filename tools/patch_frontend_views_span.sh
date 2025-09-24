#!/usr/bin/env bash
set -euo pipefail

pick_index() {
  for f in ./frontend/index.html ./index.html; do
    if [ -f "$f" ]; then echo "$f"; return 0; fi
  done
  return 1
}

IDX="$(pick_index || true)"
[ -n "${IDX:-}" ] || { echo "❌ No se encontró frontend/index.html ni index.html"; exit 1; }

if grep -q 'id="p12-stats"' "$IDX"; then
  echo "✔ Bloque #p12-stats ya presente en $IDX (nada que hacer)."
else
  echo "→ Inyectando bloque de métricas (likes/views/reports) en $IDX …"
  ts="$(date +%s)"
  cp -f "$IDX" "$IDX.bak.$ts"

  TMP="$IDX.tmp.$ts"
  awk 'BEGIN{done=0}
       /<\/body>/ && !done {
         print "  <div id=\"p12-stats\" class=\"stats\" style=\"margin:8px 0;font:14px system-ui, -apple-system, Segoe UI, Roboto, sans-serif;\">";
         print "    <span class=\"likes\" data-likes=\"0\">&#10084; <b>0</b></span>";
         print "    <span class=\"views\" data-views=\"0\" style=\"margin-left:12px;\">&#128065; <b>0</b></span>";
         print "    <span class=\"reports\" data-reports=\"0\" hidden style=\"margin-left:12px;\">&#128681; <b>0</b></span>";
         print "  </div>";
         done=1
       }
       { print }' "$IDX" > "$TMP" && mv "$TMP" "$IDX"

  echo "✓ Bloque insertado."
fi

# Verificación explícita para la sanity
if grep -q 'class="views"' "$IDX"; then
  echo "✔ Sanity: se detecta <span class=\"views\"> en $IDX"
else
  echo "❌ Sanity: NO se detecta <span class=\"views\"> en $IDX"; exit 2
fi
