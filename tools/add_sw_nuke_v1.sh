#!/usr/bin/env bash
set -euo pipefail

HTML="frontend/index.html"
[[ -f "$HTML" ]] || { echo "ERROR: falta $HTML"; exit 1; }

TS="$(date -u +%Y%m%d-%H%M%SZ)"
BAK="frontend/index.$TS.swnuke.bak"
cp -f "$HTML" "$BAK"
echo "[sw-nuke] Backup: $BAK"

python - <<'PY'
import io, re
p="frontend/index.html"
s=io.open(p,"r",encoding="utf-8").read()
orig=s

snippet = r"""
<script>
(function(){
  try{
    var q=new URLSearchParams(location.search);
    if(q.has('nosw')||q.has('nukesw')){
      if('serviceWorker' in navigator){
        navigator.serviceWorker.getRegistrations()
        .then(rs=>Promise.all(rs.map(r=>r.unregister())))
        .then(()=>{ if(window.caches){ return caches.keys().then(ks=>Promise.all(ks.map(k=>caches.delete(k)))) }})
        .finally(()=>console.log('[sw-nuke] done'));
      }
    }
  }catch(e){}
})();
</script>
"""

if "sw-nuke" not in s:
    s = re.sub(r'</head>', snippet+'\n</head>', s, count=1, flags=re.I)

if s!=orig:
    io.open(p,"w",encoding="utf-8").write(s)
    print("[sw-nuke] index.html actualizado")
else:
    print("[sw-nuke] ya estaba OK")
PY

echo "Listo."
