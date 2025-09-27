#!/usr/bin/env bash
set -euo pipefail
cand=("static/index.html" "public/index.html" "templates/index.html" "wsgiapp/templates/index.html" "index.html")
idx=""
for f in "${cand[@]}"; do [[ -f "$f" ]] && { idx="$f"; break; }; done
if [[ -z "$idx" ]]; then
  idx="$(grep -RIl --include='*.html' -e '<title>Paste12' -e 'class="brand">Paste12' 2>/dev/null | head -n1 || true)"
fi
[[ -n "$idx" ]] || { echo "No encontré index.html en el repo"; exit 1; }

python - "$idx" <<'PY'
import sys,re
p=sys.argv[1]
s=open(p,'r',encoding='utf-8').read()

# meta p12-single
if 'name="p12-single"' not in s:
    s=re.sub(r'(<meta[^>]+name="p12-built-at"[^>]*>\s*)', r'\\1  <meta name="p12-single" content="auto">\\n', s, 1)

# body data-single
if re.search(r'<body[^>]*data-single=', s) is None:
    s=s.replace('<body', '<body data-single="0"', 1)

# inline shim antes de </head>
if 'p12-safe-shim' not in s:
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
    s=s.replace('</head>', shim+'\\n</head>', 1)

open(p,'w',encoding='utf-8').write(s)
print("OK:",p)
PY
