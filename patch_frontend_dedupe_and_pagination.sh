#!/usr/bin/env bash
set -Eeuo pipefail

f="frontend/js/app.js"
[ -f "$f" ] || { echo "❌ No existe $f"; exit 1; }

cp -n "$f" "$f.bak.$(date +%s)"

python - <<'PY'
import re, json, time, pathlib
p = pathlib.Path("frontend/js/app.js")
code = p.read_text(encoding="utf-8")

# 1) Estado global: página, cargando, set de ids y set de vistas ya contadas
if "window.P12=" not in code:
    code = (
        "window.P12 = window.P12 || {};\n"
        "P12.page = 1;\n"
        "P12.loading = false;\n"
        "P12.renderedIds = new Set();\n"
        "P12.viewedOnce = new Set();\n"
    ) + code

# 2) Forzar fetch del feed con page & page_size y limpiar cuando page=1
code = re.sub(
    r"async\s+load\s*\(.*?\)\s*\{.*?\n\}",
    """async load(page=1){
  if(P12.loading) return;
  P12.loading = true;
  try{
    const r = await fetch(`/api/notes?page=${page}`);
    const d = await r.json();
    const notes = d.notes || [];
    const hasMore = !!d.has_more;
    const listEl = document.querySelector('#feed') || document.body;

    if(page === 1){
      // limpiar y reiniciar set de ids renderizados
      listEl.innerHTML = '';
      P12.renderedIds.clear();
    }

    for(const n of notes){
      if(P12.renderedIds.has(n.id)) continue; // dedupe por id
      P12.renderedIds.add(n.id);

      const card = document.createElement('div');
      card.className = 'note-card';
      card.dataset.id = n.id;
      card.innerHTML = `
        <div class="note-text"></div>
        <div class="note-meta">
          <span class="likes">❤ ${n.likes||0}</span>
          <span class="views">👁 ${n.views||0}</span>
          <span class="remaining"></span>
        </div>
      `;
      card.querySelector('.note-text').textContent = n.text || '';
      if(n.remaining != null){
        card.querySelector('.remaining').textContent = fmtRemaining(n.remaining);
      }
      listEl.appendChild(card);

      // Enviar vista solo 1 vez por sesión
      if(!P12.viewedOnce.has(n.id)){
        P12.viewedOnce.add(n.id);
        fetch(`/api/notes/${n.id}/view`, {method:'POST'}).catch(()=>{});
      }
    }

    // paginación infinita
    if(hasMore){
      P12.page = page + 1;
      attachInfiniteScroll();
    }
  }catch(e){
    console.error('load error', e);
  }finally{
    P12.loading = false;
  }
}""",
    code,
    flags=re.S
)

# 3) Helper fmtRemaining (si no existe)
if "function fmtRemaining(" not in code:
    code += """
function fmtRemaining(sec){
  sec = Math.max(0, parseInt(sec||0,10));
  const d = Math.floor(sec/86400); sec%=86400;
  const h = Math.floor(sec/3600); sec%=3600;
  const m = Math.floor(sec/60);
  if(d>0) return `${d}d ${h}h`;
  if(h>0) return `${h}h ${m}m`;
  return `${m}m`;
}
"""

# 4) Infinite scroll con listener único (once)
if "attachInfiniteScroll()" not in code:
    code += """
function attachInfiniteScroll(){
  if(P12._scrollAttached) return;
  P12._scrollAttached = true;
  const onScroll = () => {
    const nearBottom = window.innerHeight + window.scrollY >= (document.body.offsetHeight - 600);
    if(nearBottom && !P12.loading){
      P12._scrollAttached = false; // se re-adjunta al terminar load
      window.removeEventListener('scroll', onScroll, {passive:true});
      // pedir siguiente página
      window.requestAnimationFrame(()=>window.P12App.load(P12.page));
    }
  };
  window.addEventListener('scroll', onScroll, {passive:true});
}
"""

# 5) Bootstrap único
if "window.P12App" not in code:
    code = (
        "window.P12App = { load: async function(page){ return await window.load(page); } };\n"
        + code
    )

p.write_text(code, encoding="utf-8")
print("✓ app.js parcheado (dedupe + paginación + vistas 1×)")
PY

echo "Ahora haz build estático si aplica (no es necesario en esta app)."
