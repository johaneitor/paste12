#!/usr/bin/env bash
set -euo pipefail

CLIENT_ID="${1:-ca-pub-9479870293204581}"

find_index() {
  local cands=(
    "./index.html"
    "./templates/index.html"
    "./static/index.html"
    "./public/index.html"
    "./frontend/index.html"
    "./web/index.html"
  )
  for f in "${cands[@]}"; do
    [[ -f "$f" ]] && grep -qi "<head" "$f" && { echo "$f"; return 0; }
  done
  # último intento: busca cualquier index.html cercano
  local f
  while IFS= read -r -d '' f; do
    grep -qi "<head" "$f" && { echo "$f"; return 0; }
  done < <(find . -maxdepth 3 -type f -iname "index.html" -print0 2>/dev/null || true)
  return 1
}

main() {
  local IDX
  if ! IDX="$(find_index)"; then
    echo "❌ No encontré index.html con <head>. Coloca el archivo y reintenta." >&2
    exit 1
  fi
  echo "→ Index: $IDX"

  # ya está insertado?
  if grep -q 'googlesyndication.com/pagead/js/adsbygoogle.js' "$IDX"; then
    echo "✔ AdSense ya presente en $IDX (no hago nada)."
    exit 0
  fi

  local TS; TS="$(date +%Y%m%d-%H%M%SZ)"
  cp -f "$IDX" "$IDX.bak.$TS"

  # inserta justo después de <head ...>
  awk -v CID="$CLIENT_ID" '
    BEGIN{done=0}
    {
      print $0
      if (!done && tolower($0) ~ /<head[^>]*>/) {
        print "<script async src=\"https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=" CID "\""
        print "     crossorigin=\"anonymous\"></script>"
        done=1
      }
    }
  ' "$IDX.bak.$TS" > "$IDX"

  echo "✔ Insertado en <head>."
  echo "   Backup: $IDX.bak.$TS"
}
main "$@"
