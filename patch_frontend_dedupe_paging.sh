#!/usr/bin/env bash
set -Eeuo pipefail
f="frontend/js/app.js"
cp "$f" "$f.bak.$(date +%s)"

# Dedup estricto por id al renderizar
grep -q 'P12.renderedIds.has' "$f" || \
  sed -i 's|for(const n of notes){|for(const n of notes){ if(P12.renderedIds.has(n.id)) continue; P12.renderedIds.add(n.id);|' "$f"

# Limpiar feed y set al cargar page=1
perl -0777 -pe 's|if\s*\(page\s*===\s*1\)\s*\{[^\}]*\}|if (page===1){ (document.querySelector("#feed")||document.body).innerHTML=""; P12.renderedIds.clear(); }|s' -i "$f"

# Adjuntar infinite scroll solo con has_more === true
perl -0777 -pe 's|if\s*\(hasMore\)\s*\{[^\}]*\}|if (hasMore === true) { P12.page = page + 1; if (window.attachInfiniteScroll) attachInfiniteScroll(); } else { if (window.detachInfiniteScroll) detachInfiniteScroll(); }|s' -i "$f"

echo "✓ app.js parcheado (dedupe + paging seguro)."
