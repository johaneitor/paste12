#!/usr/bin/env bash
set -Eeuo pipefail

mkdir -p frontend/js
cat > frontend/js/debug_overlay.js <<'JS'
(()=>{ 
  const on = /\bdebug=1\b/.test(location.search) || location.hash==="#debug";
  if(!on) return;

  function el(tag,attrs={},html=""){const e=document.createElement(tag);Object.assign(e,attrs);e.innerHTML=html;return e;}
  async function getPageData(){
    const p = (window.P12?.page)||1;
    try{
      const r = await fetch(`/api/notes?page=${p}`, {headers:{'Accept':'application/json'}});
      return await r.json();
    }catch{return {notes:[],has_more:false};}
  }
  function domStats(){
    const cards=[...document.querySelectorAll('.note-card')];
    const ids=cards.map(c=>c.dataset.id||'').filter(Boolean);
    const uniq=[...new Set(ids)];
    const counts=ids.reduce((m,id)=>((m[id]=(m[id]||0)+1),m),{});
    const dups=Object.entries(counts).filter(([,c])=>c>1).map(([id,c])=>({id,c}));
    return {cards:cards.length, uniq:uniq.length, dups};
  }

  const box=el('div',{id:'p12-debug-box'});
  Object.assign(box.style,{
    position:'fixed',top:'8px',right:'8px',zIndex:99999,
    background:'rgba(0,0,0,.85)',color:'#fff',padding:'10px 12px',
    font:'12px/1.35 system-ui, sans-serif',borderRadius:'8px',
    boxShadow:'0 6px 20px rgba(0,0,0,.35)'
  });
  box.innerHTML=`
    <div style="font-weight:700;margin-bottom:6px">P12 Debug</div>
    <div>API page: <span id="dbg-page">?</span></div>
    <div>API notes: <span id="dbg-api-count">?</span> · has_more: <span id="dbg-hm">?</span></div>
    <div>DOM cards: <span id="dbg-dom">?</span> · únicos: <span id="dbg-uniq">?</span></div>
    <div>Dup IDs: <span id="dbg-dups">—</span></div>
    <div style="margin-top:6px;display:flex;gap:6px;flex-wrap:wrap">
      <button id="dbg-hl" style="padding:4px 6px">Resaltar duplicados</button>
      <button id="dbg-rm" style="padding:4px 6px">Eliminar duplicados</button>
      <button id="dbg-x"  style="padding:4px 6px">Cerrar</button>
    </div>
  `;
  document.body.appendChild(box);

  async function refresh(){
    const data = await getPageData();
    const apiCount = (data.notes||[]).length;
    const hm = !!data.has_more;
    const page = (window.P12?.page)||1;
    const {cards,uniq,dups} = domStats();

    box.querySelector('#dbg-page').textContent = page;
    box.querySelector('#dbg-api-count').textContent = apiCount;
    box.querySelector('#dbg-hm').textContent = hm;
    box.querySelector('#dbg-dom').textContent = cards;
    box.querySelector('#dbg-uniq').textContent = uniq;
    box.querySelector('#dbg-dups').textContent = dups.length
      ? dups.slice(0,8).map(d=>`${d.id}×${d.c}`).join(', ')
      : '—';
  }
  refresh();
  const iv = setInterval(refresh, 1500);

  box.querySelector('#dbg-hl').onclick = ()=>{
    const seen=new Set();
    document.querySelectorAll('.note-card').forEach(n=>{
      const id=n.dataset.id;
      if(seen.has(id)) n.style.outline='3px solid red';
      else seen.add(id);
    });
  };
  box.querySelector('#dbg-rm').onclick = ()=>{
    const seen=new Set();
    document.querySelectorAll('.note-card').forEach(n=>{
      const id=n.dataset.id;
      if(!id) return;
      if(seen.has(id)) n.remove();
      else seen.add(id);
    });
    refresh();
  };
  box.querySelector('#dbg-x').onclick = ()=>{ clearInterval(iv); box.remove(); };
})();
JS

# inyectar en index.html si no está
if ! grep -q 'debug_overlay.js' frontend/index.html; then
  sed -i 's#</body>#  <script defer src="/js/debug_overlay.js"></script>\n</body>#' frontend/index.html
fi

echo "✅ Overlay añadido. Abre: https://paste12-rmsk.onrender.com/?debug=1"
