#!/usr/bin/env bash
set -euo pipefail

HTML="${1:-frontend/index.html}"
[[ -f "$HTML" ]] || HTML="index.html"
[[ -f "$HTML" ]] || { echo "No encuentro $HTML"; exit 1; }

cp -a "$HTML" "$HTML.bak.$(date +%s)"

if grep -q 'id="shim-parsenext-next-body"' "$HTML"; then
  echo "→ shim parseNext ya presente, no hago nada"
  exit 0
fi

awk '
  /<\/body>/ && !done {
    print "<script id=\"shim-parsenext-next-body\">"
    print "(function(){"
    print "  if(typeof window.parseNext!==\"function\"){ return; }"
    print "  const orig=parseNext;"
    print "  window.parseNext = function(res, j){"
    print "    let u = orig(res, j);"
    print "    if(!u && j && j.next && j.next.cursor_ts && (j.next.cursor_id!=null)){"
    print "      u = `/api/notes?cursor_ts=${encodeURIComponent(j.next.cursor_ts)}&cursor_id=${j.next.cursor_id}`;"
    print "    }"
    print "    return u;"
    print "  };"
    print "})();"
    print "</script>"
    print
    done=1
  }
  { print }
' "$HTML" > "$HTML.tmp"

mv "$HTML.tmp" "$HTML"
echo "✓ shim parseNext (j.next) inyectado en $HTML"
