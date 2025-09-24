#!/usr/bin/env bash
set -euo pipefail
f="frontend/index.html"
[ -f "$f" ] || { echo "ERR: no existe $f"; exit 1; }

if grep -q 'class="views"' "$f"; then
  echo "✔ views/likes/reports ya presente en $f"
  exit 0
fi

tmp="$f.tmp.$$"
awk '
  /<\/body>/ && !done {
    print "<div id=\"p12-stats\" style=\"display:none\">";
    print "  <span class=\"views\"></span>";
    print "  <span class=\"likes\"></span>";
    print "  <span class=\"reports\"></span>";
    print "</div>";
    print "<script id=\"p12-stats-shim\">";
    print "(function(){";
    print "  function by(sel){return document.querySelector(sel)}";
    print "  function show(n){";
    print "    var box=by(\"#p12-stats\"); if(!box||!n) return;";
    print "    var v=by(\"#p12-stats .views\"), l=by(\"#p12-stats .likes\"), r=by(\"#p12-stats .reports\");";
    print "    if(v) v.textContent = (n.views||0)+\" views\";";
    print "    if(l) l.textContent = (n.likes||0)+\" likes\";";
    print "    if(r) r.textContent = (n.reports||0)+\" reports\";";
    print "    box.style.display = \"block\";";
    print "  }";
    print "  window.p12=window.p12||{};";
    print "  // Exponer hook opcional: window.p12.onNote(note)";
    print "  if(!window.p12.onNote){ window.p12.onNote = show; }";
    print "})();";
    print "</script>";
    done=1
  }
  { print }
' "$f" > "$tmp"
mv "$tmp" "$f"
echo "✔ Insertado bloque views/likes/reports en $f"
