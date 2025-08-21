#!/usr/bin/env bash
set -Eeuo pipefail

mkdir -p frontend/js
cat > frontend/js/stability_patch.js <<'JS'
(()=> {
  function dedupe(){
    const cards = Array.from(document.querySelectorAll('.note-card[data-id]'));
    const seen = new Set();
    let removed = 0;
    for(const c of cards){
      const id = c.dataset.id;
      if(!id) continue;
      if(seen.has(id)){ c.remove(); removed++; }
      else seen.add(id);
    }
    return removed;
  }

  // corre al cargar y luego cada 1.5s
  const run = ()=>{ try{ dedupe(); }catch{} };
  document.addEventListener('DOMContentLoaded', run, {once:true});
  setInterval(run, 1500);

  // si hay mutaciones (llegan nuevas notas), dedupe inmediato
  try{
    const mo = new MutationObserver(()=>{ try{ dedupe(); }catch{} });
    mo.observe(document.documentElement, {childList:true, subtree:true});
  }catch{}
})();
JS

# asegurar que se incluye en index.html
if ! grep -q 'stability_patch.js' frontend/index.html; then
  sed -i 's#</body>#  <script defer src="/js/stability_patch.js"></script>\n</body>#' frontend/index.html
fi

echo "✅ stability_patch.js instalado. Recarga el sitio."
