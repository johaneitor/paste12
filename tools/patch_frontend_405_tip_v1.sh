#!/usr/bin/env bash
set -euo pipefail
HTML="frontend/index.html"
[[ -f "$HTML" ]] || { echo "ERROR: falta $HTML"; exit 1; }
TS="$(date -u +%Y%m%d-%H%M%SZ)"; BAK="frontend/index.$TS.405tip.bak"
cp -f "$HTML" "$BAK"; echo "[backup] $BAK"

# Inyecta un wrapper de fetch que marca 405 y sugiere revisar dominio
awk '
/<\/body>/ && !x{
  print "<script id=\"p12-405-tip\">(function(){try{"
  print "  var _f = window.fetch; if(!_f) return;"
  print "  window.fetch = function(u,i){"
  print "    return _f.apply(this,arguments).then(function(r){"
  print "      try{ if(r && r.status===405){"
  print "        var host = location.hostname;"
  print "        var tip  = (host.indexOf(\"paste12-\")===-1)? \" ¿Estás en paste12-rmsk.onrender.com? (ojo: pastel2 no es lo mismo)\" : \" Endpoint sin POST habilitado.\";"
  print "        var box = document.getElementById(\"msg\");"
  print "        if(!box){ box=document.createElement(\"div\"); box.id=\"msg\"; (document.body||document.documentElement).prepend(box); }"
  print "        box.className=\"error\"; box.textContent = \"Error HTTP 405.\" + tip;"
  print "      }}catch(_){ }"
  print "      return r;"
  print "    });"
  print "  };"
  print "}catch(_){}})();</script>"
  x=1
}
{print}
' "$HTML" > "$HTML.tmp" && mv "$HTML.tmp" "$HTML"
echo "OK: 405 guard inyectado."
