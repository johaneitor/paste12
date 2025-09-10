#!/usr/bin/env python3
import pathlib, shutil

cands=[pathlib.Path("backend/static/index.html"),pathlib.Path("frontend/index.html"),pathlib.Path("index.html")]
t=next((p for p in cands if p.exists()),None)
if not t: raise SystemExit("✗ no encontré index.html")
src=t.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n")
if "<!-- MINI-SHIM v3.2 START -->" in src:
    print("OK: shim v3.2 ya presente"); raise SystemExit

JS=r"""
<!-- MINI-SHIM v3.2 START -->
<script>
(()=>{'use strict';
const Q = new URLSearchParams(location.search);
if(!Q.has('shim')) return;   // ACTIVACIÓN EXPLÍCITA

// Opcional: desregistrar SW si hay ?nosw=1
if((Q.has('nosw')||Q.has('debug')) && 'serviceWorker' in navigator){
  try{ navigator.serviceWorker.getRegistrations().then(rs=>rs.forEach(r=>r.unregister())); }catch(e){}
  try{ if(caches&&caches.keys) caches.keys().then(ks=>ks.forEach(k=>caches.delete(k))); }catch(e){}
}
// Quitar banners de "nueva versión disponible"
for(const n of Array.from(document.querySelectorAll('div,section')).slice(0,200)){
  const tx=(n.textContent||'').toLowerCase();
  if(tx.includes('nueva versión disponible')||tx.includes('actualiza para ver')){ n.remove(); }
}

const $=(s,c=document)=>c.querySelector(s);
const $$=(s,c=document)=>Array.from(c.querySelectorAll(s));
const FEED='[data-notes],[data-feed],#notes,#feed';
let feed=$(FEED) || (function(){const d=document.createElement('div'); d.id='feed'; document.body.appendChild(d); return d;})();
const esc=s=>(s??'').toString().replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));

// --- PUBLICAR (textarea cercano al botón "Publicar") ---
for(const f of $$('form')){ if(f.querySelector('textarea')) f.addEventListener('submit',e=>{e.preventDefault();e.stopImmediatePropagation();},{capture:true}); }
const pubBtns=$$('button,[role="button"]').filter(b=>/publicar/i.test(b.textContent||''));
for(const b of pubBtns){ b.type='button'; b.addEventListener('click', async (ev)=>{
  ev.preventDefault(); ev.stopImmediatePropagation();
  const scope=b.closest('form,section,article,div')||document;
  const ta=scope.querySelector('textarea')||document.querySelector('textarea');
  const sel=scope.querySelector('select[name*="hour"],select[name*="hora"],select')||null;
  const text=(ta&&ta.value||'').trim(); const hours=(sel&&parseInt(sel.value,10))||12;
  if(!text){ alert('Escribí tu nota.'); return; }
  let ok=false, j=null;
  try{
    const r=await fetch('/api/notes',{method:'POST',credentials:'include',headers:{'Content-Type':'application/json'},body:JSON.stringify({text, hours})});
    if(r.ok){ j=await r.json(); ok=true; }
  }catch(e){}
  if(!ok){
    const body=new URLSearchParams({text, hours:String(hours)}).toString();
    const r2=await fetch('/api/notes',{method:'POST',credentials:'include',headers:{'Content-Type':'application/x-www-form-urlencoded'},body});
    if(r2.ok){ j=await r2.json(); ok=true; }
  }
  if(!ok){ alert('No se pudo publicar (reintenta).'); return; }
  const item=j.item||j; if(item && item.id){ const n=render(item,true); feed.prepend(n); attach(n); if(ta) ta.value=''; }
});}

// --- ACCIONES (like/report/share) y "Ver más" ---
function actionsHTML(it){
  const id=it.id, likes=it.likes??0, views=it.views??0;
  return `<div class="mini-actions" data-mini="1" style="display:flex;gap:10px;flex-wrap:wrap;margin-top:6px;">
    <button class="mini-like" data-id="${id}" style="padding:6px 10px;border:1px solid #e5e7eb;border-radius:999px;background:#fff;">❤️ <span data-like>${likes}</span></button>
    <span title="vistas" style="opacity:.7;">👁️ ${views}</span>
    <button class="mini-report" data-id="${id}" style="padding:6px 10px;border:1px solid #fee2e2;border-radius:999px;background:#fff;">🚩 Reportar</button>
    <button class="mini-share" data-id="${id}" style="padding:6px 10px;border:1px solid #e5e7eb;border-radius:999px;background:#fff;">🔗 Compartir</button>
  </div>`;
}
function serverCardClass(){ const c=$(FEED+' [data-id]'); return c?c.className:''; }
const CARD_CLASS=serverCardClass();
function render(item,hl=false){
  const ts=item.timestamp?new Date(item.timestamp.replace(' ','T')).toLocaleString():''; 
  const el=document.createElement('article'); el.setAttribute('data-id',item.id);
  el.className=CARD_CLASS || 'mini-card';
  if(!CARD_CLASS){ el.style.cssText='background:#fff;border:1px solid #eee;border-radius:16px;padding:12px;margin:12px 0;'; }
  el.innerHTML=`<header style="font-size:.85rem;color:#6b7280;display:flex;gap:10px;align-items:center;flex-wrap:wrap;">
      <span>#${item.id}</span>${ts?`<time>${esc(ts)}</time>`:''}
    </header>
    <div class="mini-text" data-full="1" style="margin-top:8px;white-space:pre-wrap;">${esc(item.text||'')}</div>
    ${actionsHTML(item)}
  `;
  if(hl && !CARD_CLASS) el.style.boxShadow='0 10px 20px rgba(0,0,0,.06)';
  return el;
}
function attach(scope=document){
  // Añade acciones si faltan
  for(const card of $$('[data-id]:not([data-mini-patched])', scope)){
    if(!card.querySelector('[data-mini]')){
      const id=card.getAttribute('data-id') || (card.textContent||'').match(/#(\d+)/)?.[1];
      if(!id) continue;
      const host=card.querySelector('.mini-text')||card;
      const d=document.createElement('div'); d.innerHTML=actionsHTML({id,likes:0,views:0});
      host.appendChild(d.firstElementChild);
    }
    card.setAttribute('data-mini-patched','1');
  }
  // listeners
  for(const b of $$('.mini-like', scope)){ b.onclick=async ()=>{ const id=b.getAttribute('data-id'); try{ const r=await fetch(`/api/notes/${id}/like`,{method:'POST',credentials:'include'}); const j=await r.json(); const s=b.querySelector('[data-like]'); if(s&&j&&typeof j.likes!=='undefined') s.textContent=j.likes; }catch(e){} }; }
  for(const b of $$('.mini-report', scope)){ b.onclick=async ()=>{ const id=b.getAttribute('data-id'); b.disabled=true; try{ await fetch(`/api/notes/${id}/report`,{method:'POST',credentials:'include'}); b.textContent='✅ Reportado'; }catch(e){ b.disabled=false; } }; }
  for(const b of $$('.mini-share', scope)){ b.onclick=async ()=>{ const id=b.getAttribute('data-id'); const url=new URL(location.href); url.hash=`note-${id}`; if(navigator.share){ try{ await navigator.share({title:'Paste12',text:`#${id}`,url:String(url)});}catch(e){} } else { try{ await navigator.clipboard.writeText(String(url)); b.textContent='📋 Copiado'; setTimeout(()=>b.textContent='🔗 Compartir',1200);}catch(e){} } }; }
}
attach(document);

// "Ver más" => GET /api/notes/:id
document.addEventListener('click', async (e)=>{
  const t=e.target; if(!t) return;
  const txt=(t.textContent||'').trim().toLowerCase();
  if(txt==='ver más' || t.hasAttribute('data-more') || t.hasAttribute('data-expand')){
    e.preventDefault(); e.stopPropagation();
    const card=t.closest('[data-id]'); if(!card) return;
    const id=card.getAttribute('data-id') || (card.textContent||'').match(/#(\d+)/)?.[1];
    const box=card.querySelector('.mini-text')||card;
    if(!id || box.getAttribute('data-full')==='1') return;
    try{ const r=await fetch(`/api/notes/${id}`,{credentials:'include'}); const j=await r.json(); const it=j.item||j; if(it&&it.text){ box.textContent=it.text; box.setAttribute('data-full','1'); }}catch(_){}
  }
},{capture:true});

// --- Paginación keyset ---
let nextURL=null, loading=false;
function parseNextFromHeaders(res){
  const link=res.headers.get('Link')||res.headers.get('link'); if(!link) return null;
  const m=link.match(/<([^>]+)>;\s*rel="?next"?/i); return m?m[1]:null;
}
async function fetchPage(url){
  loading=true;
  try{
    const res=await fetch(url,{credentials:'include'});
    const j=await res.json().catch(()=>({}));
    const items=(j&&j.items)||[];
    nextURL=(j&&j.next&&j.next.cursor_ts&&j.next.cursor_id)
      ? `/api/notes?cursor_ts=${encodeURIComponent(j.next.cursor_ts)}&cursor_id=${j.next.cursor_id}`
      : parseNextFromHeaders(res);
    const frag=document.createElement('div');
    for(const it of items){ frag.appendChild(render(it,false)); }
    feed.appendChild(frag); attach(frag); ensureLoadMore();
  }catch(e){ ensureLoadMore(true); } finally{ loading=false; }
}
function ensureLoadMore(err=false){
  let btn=document.getElementById('shim-load-more'); if(btn) btn.remove();
  if(!nextURL) return;
  btn=document.createElement('button'); btn.id='shim-load-more';
  btn.textContent=err?'Reintentar':'Cargar más';
  btn.style.cssText='display:block;margin:12px auto;padding:.6rem 1rem;border-radius:999px;border:1px solid #e5e7eb;background:#fff;';
  btn.onclick=()=>{ if(!loading) fetchPage(nextURL); };
  feed.appendChild(btn);
}
// kickoff
fetchPage('/api/notes?limit=10');
})();
</script>
<!-- MINI-SHIM v3.2 END -->
"""

def insert_before_body_end(s, block):
    low=s.lower()
    i=low.rfind("</body>")
    return (s[:i] + "\n" + block + "\n" + s[i:]) if i!=-1 else (s + "\n" + block + "\n")

bak=t.with_suffix(t.suffix+".shim_v3_2.bak")
if not bak.exists(): shutil.copyfile(t, bak)
t.write_text(insert_before_body_end(src, JS), encoding="utf-8")
print(f"patched: shim v3.2 insertado | backup={bak.name}")
