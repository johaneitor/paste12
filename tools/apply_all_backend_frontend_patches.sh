#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
HTML_CANDIDATES=("frontend/index.html" "index.html")
HTML=""
for h in "${HTML_CANDIDATES[@]}"; do
  [[ -f "$h" ]] && HTML="$h" && break
done
[[ -n "$HTML" ]] || { echo "No encontré index.html (frontend)."; exit 1; }

echo "== Aplicando parches =="
tools/patch_backend_export_application.sh

tools/patch_front_views_span.sh "$HTML"
tools/patch_front_publish_fallback_json.sh "$HTML"
tools/patch_front_parse_next_body.sh "$HTML"
tools/patch_front_hide_menu_expand.sh "$HTML"

echo
echo "✓ Todos los parches aplicados."
echo "Siguiente paso sugerido:"
echo "  1) Tests locales contra staging"
echo "  2) Push"
echo "  3) Deploy en Render (Clear build cache + Deploy)"
