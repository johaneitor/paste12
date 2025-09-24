#!/usr/bin/env bash
set -euo pipefail
files=()
[ -f backend/static/index.html ] && files+=(backend/static/index.html)
[ -f frontend/index.html ]       && files+=(frontend/index.html)
[ ${#files[@]} -eq 0 ] && { echo "✗ no hay index.html para limpiar"; exit 0; }

clean_one() {
  local f="$1"
  local bak="${f}.pre_v7clean.bak"
  [ -f "$bak" ] || cp -f "$f" "$bak"

  # 1) borrar DOCTYPE incrustado dentro de <script> (documento duplicado)
  awk '
    BEGIN{skip=0}
    /<script[> ]/{
      if ($0 ~ /<!doctype[[:space:]]+html/i) { skip=1; next }
    }
    skip && /<\/script>/ { skip=0; next }
    skip { next }
    { print }
  ' "$f" > "$f.tmp1"

  # 2) quitar hotfix v4
  sed -E '/<script[^>]*id="p12-hotfix-v4"[^>]*>/,/<\/script>/d' "$f.tmp1" > "$f.tmp2"

  # 3) quitar consolidated v6 (bloque con comentarios)
  sed -E '/P12 CONSOLIDATED HOTFIX v6/,/\/P12 CONSOLIDATED HOTFIX v6/d' "$f.tmp2" > "$f.tmp3"

  # 4) quitar view-observer legacy
  sed -E '/* view-observer:start */,/* view-observer:end */d' "$f.tmp3" > "$f.tmp4"

  # 5) asegurarnos que queda v7
  if ! grep -q 'id="p12-cohesion-v7"' "$f.tmp4"; then
    echo "✗ WARNING: no encontré v7 en $f (se deja intacto, revisa manualmente)" >&2
  fi

  mv -f "$f.tmp4" "$f"
  rm -f "$f.tmp1" "$f.tmp2" "$f.tmp3" || true
  echo "OK: limpiado $f | backup=$(basename "$bak")"
}

for f in "${files[@]}"; do clean_one "$f"; done
