#!/usr/bin/env bash
set -euo pipefail
ASOF="${1:-}"; [ -n "$ASOF" ] || { echo "uso: $0 '2025-09-11 18:00'"; exit 2; }
TS="$(date -u +%Y%m%d-%H%M%SZ)"
paths=(backend/static/index.html frontend/index.html)

for p in "${paths[@]}"; do
  [ -f "$p" ] || { echo "✗ falta $p"; exit 1; }
done

echo "== buscando commits anteriores a: $ASOF =="
declare -A rev
for p in "${paths[@]}"; do
  # Busca el último commit antes de ASOF en origin/main; si no, en HEAD local.
  cid="$(git rev-list -1 --before="$ASOF" origin/main -- "$p" 2>/dev/null || true)"
  [ -z "$cid" ] && cid="$(git rev-list -1 --before="$ASOF" HEAD -- "$p" 2>/dev/null || true)"
  [ -n "$cid" ] || { echo "✗ no hallé commit para $p"; exit 1; }
  rev["$p"]="$cid"
  echo "  $p  <-  $(printf '%.10s' "$cid")"
done

backup() { local f="$1"; cp -f "$f" "${f}.pre_restore.$TS.bak"; }

restore_one() {
  local p="$1"; local cid="${rev[$p]}"; local tmp="/tmp/r.$TS.$(echo "$p"|tr / _)"
  git show "$cid:$p" > "$tmp"
  sz="$(wc -c < "$tmp" | tr -d ' ')"
  if [ "$sz" -lt 200 ]; then
    echo "✗ tamaño sospechosamente chico para $p ($sz bytes). Aborto." >&2
    exit 1
  fi
  backup "$p"
  cp -f "$tmp" "$p"
  echo "✓ restaurado $p ($sz bytes) desde $(printf '%.10s' "$cid")"
}

for p in "${paths[@]}"; do restore_one "$p"; done

# Inyecta marcador shim seguro si faltara (idempotente)
ensure_marker() {
  local f="$1"
  if ! grep -qi 'name="p12-safe-shim"' "$f"; then
    awk 'BEGIN{done=0} {print} /<head[^>]*>/ && !done { print "<meta name=\"p12-safe-shim\" content=\"1\">"; done=1 }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    echo "  + meta p12-safe-shim agregado en $(basename "$f")"
  fi
  # Nota única (solo meta informativa; el backend ya mete data-single):
  if ! grep -qi 'name="p12-single"' "$f"; then
    awk 'BEGIN{done=0} {print} /<head[^>]*>/ && !done { print "<meta name=\"p12-single\" content=\"1\">"; done=1 }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    echo "  + meta p12-single agregado en $(basename "$f")"
  fi
}
for p in "${paths[@]}"; do ensure_marker "$p"; done

echo "== tamaños finales =="
for f in "${paths[@]}"; do printf "%8s  %s\n" "$(wc -c < "$f" | tr -d ' ')" "$f"; done

# Stage + commit
git add -f "${paths[@]}"
git commit -m "revert(frontend): restaurar index as of $ASOF + meta shim/nota única (idempotente, reversible)" || true
echo "Ahora: git push origin main"
