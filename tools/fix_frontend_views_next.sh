#!/usr/bin/env bash
set -euo pipefail

find_index() {
  for f in ./frontend/index.html ./static/index.html ./index.html; do
    [[ -f "$f" ]] && { echo "$f"; return; }
  done
  return 1
}

INDEX="$(find_index || true)"
[[ -z "${INDEX:-}" ]] && { echo "❌ No se encontró index.html"; exit 1; }

echo "== Frontend: span.views en $INDEX =="

if grep -q 'class="views"' "$INDEX"; then
  echo "→ Ya existe <span class=\"views\"> (ok)"
else
  # Envolver el contador de vistas estándar
  sed -i \
    -e 's/👁 \${it\.views}/<span class="views">👁 ${it.views}<\/span>/g' \
    -e 's/👁\s\+\([0-9][0-9]*\)/<span class="views">👁 \1<\/span>/g' \
    "$INDEX" || true
  echo "→ Intenté envolver 👁 views con <span class=\"views\">"
fi

echo "Listo."
