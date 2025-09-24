#!/usr/bin/env bash
set -euo pipefail
HTML="frontend/index.html"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
[[ -f "$HTML" ]] || { echo "ERROR: falta $HTML"; exit 2; }
cp -f "$HTML" "frontend/index.${TS}.tagline.bak"
echo "[frontend] backup: frontend/index.${TS}.tagline.bak"

python - "$HTML" <<'PY'
import io,re,sys
p=sys.argv[1]
s=io.open(p,'r',encoding='utf-8').read()
orig=s

# 1) si coexisten H2 rotador y <p id="tagline">, ocultar/eliminar el <p>
has_h2 = re.search(r'id=["\']tagline-rot["\']', s, re.I)
has_p  = re.search(r'<p[^>]+id=["\']tagline["\'][^>]*>.*?</p>', s, re.I|re.S)
if has_h2 and has_p:
    s = re.sub(r'<p[^>]+id=["\']tagline["\'][^>]*>.*?</p>', '', s, flags=re.I|re.S)
    # por compat, añadimos una línea de estilo para quien llegue desde caché viejo
    s = s.replace('</head>', '<style>#tagline{display:none!important}</style>\n</head>')

# 2) fortalecer publish() (fallback multi-endpoint)
if 'function publish' in s and 'ENDPOINTS_P12' not in s:
    s = s.replace(
        "async function publish(ev){",
        "const ENDPOINTS_P12=['/api/notes','/api/note','/api/notes/create','/api/create','/api/publish'];\nasync function publish(ev){"
    )
    s = re.sub(
        r"let r=null, j=null;\s*try\{[^}]+\}\s*catch\(_\)\{\}\s*if\(!r \|\| !r\.ok\)\{[^}]+\}\s*try\{ j=await r\.json\(\); \}\s*catch\(_\)\{ j=null; \}",
        """let r=null, j=null;
for (const ep of ENDPOINTS_P12){
  try{
    r = await fetch(ep,{method:'POST',credentials:'include',headers:{'Content-Type':'application/json','Accept':'application/json'},body:JSON.stringify(body)});
  }catch(_){}
  if(!r || !r.ok){
    const fd=new URLSearchParams(); fd.set('text', text); if(body.ttl_hours) fd.set('ttl_hours', String(body.ttl_hours));
    try{ r=await fetch(ep,{method:'POST',credentials:'include',headers:{'Content-Type':'application/x-www-form-urlencoded','Accept':'application/json'},body:fd}); }catch(_){}
  }
  try{ j=await r.json(); }catch(_){ j=null; }
  if (r && r.ok && j && j.ok!==false){ break; }
}""",
        s, flags=re.S
    )

if s!=orig:
    io.open(p,'w',encoding='utf-8').write(s)
    print("[frontend] parche aplicado")
else:
    print("[frontend] ya estaba OK")
PY

echo "Listo."
