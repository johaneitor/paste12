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

  # 0) borra temporales previos si quedaron
  rm -f "$f.tmp1" "$f.tmp2" "$f.tmp3" "$f.tmp4" 2>/dev/null || true

  # 1) eliminar DOCTYPE incrustado dentro de <script> (documento duplicado)
  awk '
    BEGIN{in_script=0; drop_till_close=0}
    {
      line=$0
      if (match(line, /<script[^>]*>/i)) { in_script=1 }
      if (in_script && match(line, /<!doctype[[:space:]]+html/i)) { drop_till_close=1; next }
      if (drop_till_close) {
        if (match(line, /<\/script>/i)) { drop_till_close=0; in_script=0 }
        next
      }
      if (in_script && match(line, /<\/script>/i)) { in_script=0 }
      print line
    }
  ' "$f" > "$f.tmp1"

  # 2) quitar hotfix v4 <script id="p12-hotfix-v4">...</script>
  awk '
    BEGIN{skip=0}
    {
      if ($0 ~ /<script[^>]*id="p12-hotfix-v4"[^>]*>/) { skip=1; next }
      if (skip) { if ($0 ~ /<\/script>/) { skip=0 } ; next }
      print
    }
  ' "$f.tmp1" > "$f.tmp2"

  # 3) quitar bloque “P12 CONSOLIDATED HOTFIX v6 … /P12 CONSOLIDATED HOTFIX v6”
  awk '
    BEGIN{skip=0}
    {
      if ($0 ~ /P12 CONSOLIDATED HOTFIX v6/) { skip=1; next }
      if (skip && $0 ~ /\/P12 CONSOLIDATED HOTFIX v6/) { skip=0; next }
      if (skip) next
      print
    }
  ' "$f.tmp2" > "$f.tmp3"

  # 4) quitar bloque view-observer (/* view-observer:start */ … /* view-observer:end */) escapando literal
  awk '
    BEGIN{skip=0}
    {
      if ($0 ~ /\/\* view-observer:start \*\//) { skip=1; next }
      if (skip && $0 ~ /\/\* view-observer:end \*\//) { skip=0; next }
      if (skip) next
      print
    }
  ' "$f.tmp3" > "$f.tmp4"

  mv -f "$f.tmp4" "$f"
  rm -f "$f.tmp1" "$f.tmp2" "$f.tmp3" || true

  if grep -q 'id="p12-cohesion-v7"' "$f"; then
    echo "OK: limpiado $f (v7 presente) | backup=$(basename "$bak")"
  else
    echo "⚠ $f limpiado pero no se detecta v7; revisa manualmente" >&2
  fi
}

for f in "${files[@]}"; do clean_one "$f"; done
