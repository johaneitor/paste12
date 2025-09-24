#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
TMP="${TMPDIR:-/tmp}/feaudit.$$"; mkdir -p "$TMP"
say(){ echo -e "$*"; }
sep(){ echo "---------------------------------------------"; }

say "== FETCH index.html =="
curl -fsS "$BASE/index.html" -o "$TMP/index.html" || curl -fsS "$BASE/" -o "$TMP/index.html" || true
sz=$(wc -c < "$TMP/index.html" || echo 0); echo "bytes: $sz"; sep

say "== Assets JS detectados =="
grep -Eo '<script[^>]+src="[^"]+"' "$TMP/index.html" | sed -E 's/.*src="([^"]+)".*/\1/' | sed 's/^\/*//; s#^#/#' | awk '{print}' > "$TMP/js.list" || true
nl=$(wc -l < "$TMP/js.list" || echo 0); echo "scripts: $nl"; cat "$TMP/js.list" || true; sep

say "== Descarga y escaneo de JS =="
> "$TMP/hits.txt"
i=0
while read -r SRC; do
  [ -n "$SRC" ] || continue
  url="$BASE$SRC"
  i=$((i+1))
  dst="$TMP/js.$i.js"
  curl -fsS "$url" -o "$dst" || continue
  hits="$(grep -Eo '/api/[a-zA-Z0-9_/\?\=\&]+' "$dst" | sort -u || true)"
  echo "[$i] $SRC"; echo "$hits" | sed 's/^/  • /'
  echo "$hits" >> "$TMP/hits.txt"
done < "$TMP/js.list"
sep

say "== Heurística de compatibilidad =="
legacy_like=$(grep -E '^/api/like(\?|$)' "$TMP/hits.txt" || true)
legacy_note=$(grep -E '^/api/note(/|\?)' "$TMP/hits.txt" || true)
uses_offset=$(grep -E '/api/notes\?[^ ]*offset=' "$TMP/hits.txt" || true)
uses_keyset=$(grep -E 'cursor_(ts|id)' "$TMP/hits.txt" || true)
reads_xnext=$(grep -Ei 'X-Next-Cursor' "$TMP/index.html" "$TMP"/js.*.js 2>/dev/null || true)

echo "• legacy_like: $([ -n "$legacy_like" ] && echo SI || echo no)"
echo "• legacy_note: $([ -n "$legacy_note" ] && echo SI || echo no)"
echo "• paginación con offset=: $([ -n "$uses_offset" ] && echo SI || echo no)"
echo "• paginación keyset (cursor_ts/cursor_id): $([ -n "$uses_keyset" ] && echo SI || echo no)"
echo "• UI hace referencia a X-Next-Cursor: $([ -n "$reads_xnext" ] && echo SI || echo no)"
sep

say "== Recomendación automática =="
if [ -n "$legacy_like$legacy_note$uses_offset" ]; then
  echo "Se detectan patrones legacy. Aplicar shims de compatibilidad del backend es RECOMENDABLE."
else
  echo "No se ven patrones legacy evidentes en JS. Si igual percibís desincronía, revisá cache/versión de assets."
fi

echo
echo "TMP: $TMP"
