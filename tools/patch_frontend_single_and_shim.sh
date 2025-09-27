#!/usr/bin/env bash
set -euo pipefail
INDEX="static/index.html"
test -f "$INDEX" || INDEX="public/index.html"

# 1) insertar meta p12-single si hay query ?id=
awk '
/<meta name="p12-commit"/ && !m { print; print "  <meta name=\"p12-single\" content=\"auto\">"; m=1; next } { print }
' "$INDEX" > "$INDEX.tmp1"

# 2) body data-single=0 por defecto
awk '
/<body[^>]*>/ && !b {
  sub(/<body/,"<body data-single=\"0\"");
  b=1
} { print }
' "$INDEX.tmp1" > "$INDEX.tmp2"

# 3) inyectar shim antes del script principal
cat > static/js/p12-safe-shim.js <<'JS'
/*! p12-safe-shim */
(function(){
  // fetch JSON seguro con timeout y Accept por defecto
  window.p12FetchJson = async function(url,opts){
    const ac = new AbortController(); const t=setTimeout(()=>ac.abort(),8000);
    try{
      const r = await fetch(url, Object.assign({headers:{'Accept':'application/json'}},opts||{}, {signal:ac.signal}));
      const ct = (r.headers.get('content-type')||'').toLowerCase();
      const isJson = ct.includes('application/json');
      return { ok:r.ok, status:r.status, json: isJson? await r.json().catch(()=>null) : null };
    } finally { clearTimeout(t); }
  };
  // activar modo single si hay ?id=
  const u = new URL(location.href);
  if(u.searchParams.get('id')){
    (document.body||document.documentElement).setAttribute('data-single','1');
  }
})();
JS

awk '
/<\/head>/ && !s {
  print "  <script defer src=\"/js/p12-safe-shim.js\"></script>";
  s=1
} { print }
' "$INDEX.tmp2" > "$INDEX.tmp3"

mv "$INDEX.tmp3" "$INDEX"
rm -f "$INDEX.tmp1" "$INDEX.tmp2"
echo "OK: index parcheado con p12-single + p12-safe-shim"
