#!/usr/bin/env python3
import pathlib, shutil

cands=[pathlib.Path("backend/static/index.html"),pathlib.Path("frontend/index.html"),pathlib.Path("index.html")]
t=next((p for p in cands if p.exists()),None)
assert t, "✗ no encontré index.html"

html=t.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n")
if "<!-- MINI-CLIENT v3.1 START -->" in html:
    print("OK: mini-cliente v3.1 ya presente"); raise SystemExit

JS = r"""
<!-- MINI-CLIENT v3.1 START -->
<script>
(()=>{'use strict';
const qs=new URLSearchParams(location.search);
const NOSW=qs.has('nosw')||qs.has('debug')||qs.has('pe');
if(NOSW&&'serviceWorker'in navigator){
  try{navigator.serviceWorker.getRegistrations().then(rs=>rs.forEach(r=>r.unregister()));
      if(window.caches&&caches.keys)caches.keys().then(keys=>keys.forEach(k=>caches.delete(k)));
  }catch(e){}
}
// quita banners de update SW
for(const n of Array.from(document.querySelectorAll('div,section')).slice(0,200)){
  const tx=(n.textContent||'').toLowerCase();
  if(tx.includes('nueva versión disponible')||tx.includes('actualiza para ver')){
    n.remove();
  }
}

const $=(s,c=document)=>c.querySelector(s);
const $$=(s,c=document)=>Array.from(c.querySelectorAll(s));
const esc=s=>(s??'').toString().replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const FEED_SEL='[data-notes],[data-feed],#notes,#feed';
let feed=$(FEED_SEL); if(!feed){ feed=document.createElement('div'); feed.id='feed'; document.body.appendChild(feed); }

// ====== PUBLICAR (botón cercano + evita submit legacy) ======
const forms=$$('form');
for(const f of forms){
  if(f.querySelector('textarea')){ f.addEventListener('submit',e=>{e.preventDefault();e.stopImmediatePropagation();},{capture:true}); }
}
const pubBtns=$$('button, [role="button"]').filter(b=>/publicar/i.test(b.textContent||''));
for(const b of pubBtns){ b.setAttribute('type','button'); } // que NO envíe formulario
function nearTextarea(btn){
  const scope=btn.closest('form,section,article,div')||document;
  return scope.querySelector('textarea')||document.querySelector('textarea');
}
function nearHours(btn){
  const scope=btn.closest('form,section,article,div')||document;
  const cand=scope.querySelector('select[name*="hour"],select[name*="hora"],select')||null;
  return cand;
}
async function doPublishFrom(btn){
  const ta=nearTextarea(btn); const sel=nearHours(btn);
  const text=(ta&&ta.value||'').trim(); const hours=(sel&&parseInt(sel.value,10))||12;
  if(!text){ alert('Escribí tu nota.'); return; }
  let ok=false,j=null;
  try{
    const r=await fetch('/api/notes',{method:'POST',credentials:'include',headers:{'Content-Type':'application/json'},body:JSON.stringify({text, hours})});
    if(r.ok){ j=await r.json(); ok=true; }
    else { try{ const jj=await r.json(); if(jj&&jj.error) throw new Error(jj.error); }catch(_){ throw new Error('http_'+r.status); } }
  }catch(_){}
  if(!ok){
    const body=new URLSearchParams({text, hours:String(hours)}).toString();
    const r2=await fetch('/api/notes',{method:'POST',credentials:'include',headers:{'Content-Type':'application/x-www-form-urlencoded'},body});
    if(r2.ok){ j=await r2.json(); ok=true; }
  }
  if(!ok){ alert('No se pudo publicar (intenta de nuevo).'); return; }
  const item=j.item||j;
  if(item&&item.id){
    const node=renderCard(item,true); feed.prepend(node); attachActions(node);
    if(ta) ta.value='';
  }
}
for(const b of pubBtns){
  b.addEventListener('click',e=>{ e.preventDefault(); e.stopImmediatePropagation(); doPublishFrom(b); },{capture:true});
}

// ====== RENDER + ACCIONES ======
function actionsHTML(item){
  const id=item.id, likes=item.likes??0, views=item.views??0;
  return `
  <div class="mini-actions-unified" data-mini-actions="1" style="display:flex;gap:10px;flex-wrap:wrap;margin-top:6px;">
    <button class="mini-like" data-id="${id}" style="padding:6px 10px;border:1px solid #e5e7eb;border-radius:999px;background:#fff;">❤️ <span data-like-count>${likes}</span></button>
    <span title="vistas" style="opacity:.7;">👁️ ${views}</span>
    <button class="mini-report" data-id="${id}" style="padding:6px 10px;border:1px solid #fee2e2;border-radius:999px;background:#fff;">🚩 Reportar</button>
    <button class="mini-share" data-id="${id}" style="padding:6px 10px;border:1px solid #e5e7eb;border-radius:999px;background:#fff;">🔗 Compartir</button>
  </div>`;
}
function serverCardClass(){ const c=$(FEED_SEL+' [data-id]'); return c?c.className:''; }
const CLONE_CLASS=serverCardClass();
function renderCard(item,hl=false){
  const ts=item.timestamp?new Date(item.timestamp.replace(' ','T')).toLocaleString():''; 
  const wrap=document.createElement('article'); wrap.setAttribute('data-id',item.id);
  wrap.className=CLONE_CLASS || 'mini-card-u';
  if(!CLONE_CLASS){ wrap.style.cssText='background:#fff;border:1px solid #eee;border-radius:16px;padding:12px;margin:12px 0;'; }
  wrap.innerHTML = `
    <header style="font-size:.85rem;color:#6b7280;display:flex;gap:10px;align-items:center;flex-wrap:wrap;">
      <span>#${item.id}</span> ${ts?`<time>${esc(ts)}</time>`:''}
    </header>
    <div class="mini-text" data-full="1" style="margin-top:8px;white-space:pre-wrap;">${esc(item.text||'')}</div>
    ${actionsHTML(item)}
  `;
  if(hl && !CLONE_CLASS) wrap.style.boxShadow='0 10px 20px rgba(0,0,0,.06)';
  return wrap;
}
function attachActions(scope=document){
  // añade acciones si faltan
  for(const card of $$('[data-id]:not([data-mini-actions-patched])', scope)){
    if(!card.querySelector('[data-mini-actions]')){
      const id=card.getAttribute('data-id') || (card.textContent||'').match(/#(\d+)/)?.[1];
      if(!id) continue;
      const host=card.querySelector('.mini-text')||card;
      const div=document.createElement('div');
      div.innerHTML=actionsHTML({id,likes:0,views:0});
      host.appendChild(div.firstElementChild);
    }
    card.setAttribute('data-mini-actions-patched','1');
  }
  // like/report/share
  for(const btn of $$('.mini-like', scope)){
    btn.onclick=async ()=>{
      const id=btn.getAttribute('data-id');
      try{ const r=await fetch(`/api/notes/${id}/like`,{method:'POST',credentials:'include'}); const j=await r.json(); const s=btn.querySelector('[data-like-count]'); if(s&&j&&typeof j.likes!=='undefined') s.textContent=j.likes; }catch(e){}
    };
  }
  for(const btn of $$('.mini-report', scope)){
    btn.onclick=async ()=>{
      const id=btn.getAttribute('data-id'); btn.disabled=true;
      try{ await fetch(`/api/notes/${id}/report`,{method:'POST',credentials:'include'}); btn.textContent='✅ Reportado'; }catch(e){ btn.disabled=false; }
    };
  }
  for(const btn of $$('.mini-share', scope)){
    btn.onclick=async ()=>{
      const id=btn.getAttribute('data-id'); const url=new URL(location.href); url.hash=`note-${id}`;
      if(navigator.share){ try{ await navigator.share({title:'Paste12',text:`#${id}`,url:url.toString()}); }catch(e){} }
      else{ try{ await navigator.clipboard.writeText(url.toString()); btn.textContent='📋 Copiado'; setTimeout(()=>btn.textContent='🔗 Compartir',1200);}catch(e){} }
    };
  }
}
attachActions(document);

// ====== "Ver más" dentro de tarjetas ======
feed.addEventListener('click', async (e)=>{
  const t=e.target; const txt=(t.textContent||'').trim().toLowerCase();
  if(txt==='ver más' || t.matches('[data-more],[data-expand]')){
    e.preventDefault(); e.stopPropagation();
    const card=t.closest('[data-id]'); if(!card) return;
    const id=card.getAttribute('data-id') || (card.textContent||'').match(/#(\d+)/)?.[1];
    const box=card.querySelector('.mini-text')||card;
    // si ya está completo no hagas nada
    if(box.getAttribute('data-full')==='1') return;
    try{
      const r=await fetch(`/api/notes/${id}`,{credentials:'include'}); const j=await r.json();
      const item=j.item||j;
      if(item&&item.text){ box.textContent=item.text; box.setAttribute('data-full','1'); }
    }catch(_){}
  }
}, {capture:true});

// ====== Paginación keyset ======
let nextURL=null, loading=false;
function parseNextLink(res){
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
      : parseNextLink(res);
    const frag=document.createElement('div');
    for(const it of items){ frag.appendChild(renderCard(it,false)); }
    feed.appendChild(frag); attachActions(frag);
    ensureLoadMore();
  }catch(e){ ensureLoadMore(true); } finally{ loading=false; }
}
function ensureLoadMore(err=false){
  let btn=document.getElementById('mini-load-more'); if(btn) btn.remove();
  if(!nextURL) return;
  btn=document.createElement('button'); btn.id='mini-load-more';
  btn.textContent=err?'Reintentar':'Cargar más';
  btn.style.cssText='display:block;margin:12px auto;padding:.6rem 1rem;border-radius:999px;border:1px solid #e5e7eb;background:#fff;';
  btn.onclick=()=>{ if(!loading) fetchPage(nextURL); };
  feed.appendChild(btn);
}
// boot: siempre calculamos next agregando una llamada controlada
fetchPage('/api/notes?limit=10');
})();
</script>
<!-- MINI-CLIENT v3.1 END -->
"""

def insert_before_body_end(s, block):
    low = s.lower()
    pos = low.rfind("</body>")
    return (s[:pos] + "\n" + block + "\n" + s[pos:]) if pos!=-1 else (s + "\n" + block + "\n")

bak=t.with_suffix(t.suffix+".mini_client_v3_1.bak")
if not bak.exists(): shutil.copyfile(t, bak)
t.write_text(insert_before_body_end(html, JS), encoding="utf-8")
print(f"patched: mini-cliente v3.1 insertado | backup={bak.name}")
