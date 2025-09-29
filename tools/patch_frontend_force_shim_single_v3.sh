#!/usr/bin/env bash
set -euo pipefail
# Parchea TODOS los index.html que existan entre estas rutas canónicas
cands=( "backend/static/index.html" "static/index.html" "public/index.html" "index.html" "wsgiapp/templates/index.html" )
patched=0
for IDX in "${cands[@]}"; do
  [[ -f "$IDX" ]] || continue
  python - "$IDX" <<'PY'
import sys,re,io
p=sys.argv[1]
s=io.open(p,'r',encoding='utf-8').read()

# 1) <meta name="p12-safe-shim"> dentro de <head>
if re.search(r'name=["\']p12-safe-shim["\']', s, re.I) is None:
    s=re.sub(r'</head>', '  <meta name="p12-safe-shim" content="1">\n</head>', s, count=1, flags=re.I)

# 2) detector single: <body data-single="1"> (si ya tiene data-single, lo pone en 1)
if re.search(r'<body[^>]*data-single=', s, re.I):
    s=re.sub(r'(<body[^>]*data-single=)["\'][^"\']*', r'\1"1', s, flags=re.I)
else:
    s=re.sub(r'<body', '<body data-single="1"', s, count=1, flags=re.I)

# 3) inline shim (si no está el marcador p12-safe-shim en scripts)
if re.search(r'p12-safe-shim', s, re.I) is None:
    shim = r"""
  <script>
  /*! p12-safe-shim */
  (function(){
    window.p12FetchJson = async function(url,opts){
      const ac = new AbortController(); const t=setTimeout(()=>ac.abort(),8000);
      try{
        const r = await fetch(url, Object.assign({headers:{'Accept':'application/json'}},opts||{}, {signal:ac.signal}));
        const ct = (r.headers.get('content-type')||'').toLowerCase();
        const isJson = ct.includes('application/json');
        return { ok:r.ok, status:r.status, json: isJson? await r.json().catch(()=>null) : null };
      } finally { clearTimeout(t); }
    };
    try{
      var u=new URL(location.href);
      if(u.searchParams.get('id')){
        (document.body||document.documentElement).setAttribute('data-single','1');
      }
    }catch(_){}
  })();
  </script>
"""
    s = re.sub(r'</head>', shim+'\n</head>', s, count=1, flags=re.I)

io.open(p,'w',encoding='utf-8').write(s)
print("OK", p)
PY
  patched=$((patched+1))
done

echo "Patched $patched index.html file(s)."
# Commit si hubo cambios
if ! git diff --quiet; then
  git add -A
  git commit -m "FE: forzar p12-safe-shim + data-single=1 en todos los index.html (robusto)"
fi
