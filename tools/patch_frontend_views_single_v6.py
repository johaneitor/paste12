#!/usr/bin/env python3
import re, sys, pathlib, shutil

FILES = [p for p in (
    pathlib.Path("backend/static/index.html"),
    pathlib.Path("frontend/index.html"),
    pathlib.Path("index.html"),
) if p.exists()]

if not FILES:
    print("✗ No encontré index.html"); sys.exit(0)

HOTFIX_IDS = (r"p12-hotfix-v6", r"p12-hotfix-v5", r"p12-hotfix-v4")

JS = r"""
<script id="p12-hotfix-v6">
(()=>{'use strict';
if (window.__P12_HOTFIX_V6__) return; window.__P12_HOTFIX_V6__=true;

const $=(s,c=document)=>c.querySelector(s);
const Q=new URLSearchParams(location.search);
const esc=s=>(s??'').toString().replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));

if((Q.has('nosw')||Q.has('debug')) && 'serviceWorker' in navigator){
  try{navigator.serviceWorker.getRegistrations().then(rs=>rs.forEach(r=>r.unregister()));}catch(e){}
  try{if(caches&&caches.keys) caches.keys().then(ks=>ks.forEach(k=>caches.delete(k)));}catch(e){}
}

(function killBanners(){
  const BAD=[/nueva versión/i,/actualiza.*últimos cambios/i,/update available/i];
  for(const el of Array.from(document.body.querySelectorAll('*'))){
    const t=(el.textContent||'').trim(); if(!t) continue;
    if(BAD.some(rx=>rx.test(t))){
      try{ el.closest('[role="alert"],.toast,.snackbar,.banner')?.remove(); }catch(_){}
      try{ el.remove(); }catch(_){}
    }
  }
})();

let FEED = document.querySelector('#list, .list, [data-notes], [data-feed], #notes, #feed');
if(!FEED){ FEED=document.createElement('section'); FEED.id='list'; (document.body||document.documentElement).append(FEED); }

function flash(ok,msg){
  let el = $('#msg'); if(!el){ el=document.createElement('div'); el.id='msg'; (document.body||document.documentElement).prepend(el); }
  el.className = ok?'ok':'error'; el.textContent = msg;
  setTimeout(()=>{ el.className='hidden'; el.textContent=''; }, 2000);
}

function cardHTML(it){
  const txt = it.text || it.content || it.summary || '';
  const needsMore = txt.length > 180;
  const short = needsMore ? (txt.slice(0,160)+'…') : txt;
  return `
  <article class="note" data-id="${it.id}">
    <div data-text="1" data-full="${esc(txt)}">${esc(short)||'(sin texto)'}</div>
    <div class="meta">#${it.id}
      · <span class="likes">❤ ${it.likes??0}</span>
      · <span class="views">👁 ${it.views??0}</span>
      <button class="act like" type="button" aria-label="Me gusta">❤</button>
      <button class="act more" type="button" aria-label="Más">⋯</button>
    </div>
    <div class="menu hidden">
      ${needsMore?'<button class="expand" type="button">Ver más</button>':''}
      <button class="share"  type="button">Compartir</button>
      <button class="report" type="button">Reportar 🚩</button>
    </div>
  </article>`;
}

function appendItems(items){
  if(!items||!items.length) return;
  const wrap=document.createElement('div'); wrap.innerHTML=items.map(cardHTML).join('');
  FEED.append(...wrap.children);
  attachObservers();
}

document.addEventListener('click', async (e)=>{
  const art = e.target.closest && e.target.closest('article.note'); if(!art) return;
  const id  = art.getAttribute('data-id'); if(!id) return;

  const btnLike = e.target.closest('button.like');
  const btnMore = e.target.closest('button.more');
  const btnShare= e.target.closest('button.share');
  const btnRpt  = e.target.closest('button.report');
  const btnExp  = e.target.closest('button.expand');

  try{
    if(btnLike){
      if(btnLike.disabled) return; btnLike.disabled=true;
      let j={}; try{
        const r=await fetch(`/api/notes/${id}/like`,{method:'POST',credentials:'include',headers:{'Accept':'application/json'}});
        j = await r.json().catch(()=>({}));
      }catch(_){}
      const el = art.querySelector('.likes'); if(el && typeof j.likes!=='undefined') el.textContent='❤ '+j.likes;
      btnLike.disabled=false;
    }else if(btnMore){
      art.querySelector('.menu')?.classList.toggle('hidden');
    }else if(btnShare){
      const url = `${location.origin}/?id=${id}`;
      if(navigator.share){ await navigator.share({title:`Nota #${id}`, url}); }
      else{ await navigator.clipboard.writeText(url); flash(true,'Link copiado'); }
      art.querySelector('.menu')?.classList.add('hidden');
    }else if(btnRpt){
      let j={}; try{
        const r=await fetch(`/api/notes/${id}/report`,{method:'POST',credentials:'include',headers:{'Accept':'application/json'}});
        j=await r.json().catch(()=>({}));
      }catch(_){}
      if(j?.removed){ art.remove(); flash(true,'Nota eliminada'); }
      else{ flash(true,'Reporte enviado'); }
      art.querySelector('.menu')?.classList.add('hidden');
    }else if(btnExp){
      const box=art.querySelector('[data-text]'); if(!box) return;
      const full=box.getAttribute('data-full')||'';
      const expanded = btnExp.getAttribute('data-expanded')==='1';
      if(expanded){ box.textContent=(full.length>180? full.slice(0,160)+'…' : full); btnExp.textContent='Ver más'; btnExp.setAttribute('data-expanded','0'); }
      else       { box.textContent=full; btnExp.textContent='Ver menos'; btnExp.setAttribute('data-expanded','1'); }
    }
  }catch(_){}
}, {capture:true});

// publicar
function pickTextarea(){ return document.querySelector('textarea[name=text], #text, textarea'); }
function pickTTL(){ return document.querySelector('input[name=ttl_hours], #ttl, select[name=ttl_hours], select'); }
function validateText(s){ return (s||'').trim().length >= 12; }
async function publish(ev){
  ev && ev.preventDefault && ev.preventDefault();
  const ta=pickTextarea(), ttl=pickTTL(); const text=(ta?.value||'').trim();
  if(!validateText(text)){ flash(false,'Escribí un poco más (≥ 12).'); return; }
  const body={text}; const v=parseInt(ttl?.value||'',10); if(Number.isFinite(v)&&v>0) body.ttl_hours=v;
  let r=null, j=null;
  try{
    r=await fetch('/api/notes',{method:'POST',credentials:'include',headers:{'Content-Type':'application/json','Accept':'application/json'},body:JSON.stringify(body)});
  }catch(_){}
  if(!r || !r.ok){
    const fd=new URLSearchParams(); fd.set('text',text); if(body.ttl_hours) fd.set('ttl_hours',String(body.ttl_hours));
    try{ r=await fetch('/api/notes',{method:'POST',credentials:'include',headers:{'Content-Type':'application/x-www-form-urlencoded','Accept':'application/json'},body:fd}); }catch(_){}
  }
  try{ j=await r.json(); }catch(_){ j=null; }
  if(!r || !r.ok || !j || j.ok===false){ flash(false,(j&&j.error)||('Error HTTP '+(r&&r.status))); return; }
  const it=j.item||{id:j.id,text,likes:j.likes||0,views:0,timestamp:new Date().toISOString()};
  const d=document.createElement('div'); d.innerHTML=cardHTML(it); FEED.prepend(d.firstElementChild);
  if(ta) ta.value=''; if(ttl) ttl.value=''; flash(true,'Publicado ✅');
}
window.addEventListener('DOMContentLoaded', ()=>{
  const btn=document.getElementById('send'); if(btn) btn.addEventListener('click', publish, {capture:true});
  const ta=pickTextarea(); if(ta){ ta.addEventListener('keydown',e=>{ if(e.key==='Enter'&&(e.ctrlKey||e.metaKey)) publish(e); }); }
});

// paginación + “cargar más”
let nextURL=null, loading=false, seenIds=new Set();
function moreButton(){ let b=document.getElementById('p12-more'); if(!b){ b=document.createElement('button'); b.id='p12-more'; b.type='button'; b.textContent='Cargar más'; b.style.cssText='display:block;margin:12px auto;padding:.6rem 1rem;border-radius:999px;border:1px solid #e5e7eb;background:#fff;'; FEED.after(b); b.onclick=()=>{ if(nextURL && !loading) fetchPage(nextURL); }; } return b; }
function setMoreVisible(v){ moreButton().style.display = v ? '' : 'none'; }
function parseNext(res){
  nextURL=null; const link=res.headers.get('Link')||res.headers.get('link');
  if(link){ const m=/<([^>]+)>;\s*rel="?next"?/i.exec(link); if(m) nextURL=m[1]; }
  if(!nextURL){
    try{ const xn=JSON.parse(res.headers.get('X-Next-Cursor')||'null'); if(xn&&xn.cursor_ts&&xn.cursor_id){ nextURL=`/api/notes?cursor_ts=${encodeURIComponent(xn.cursor_ts)}&cursor_id=${xn.cursor_id}`; } }catch(_){}
  }
  setMoreVisible(!!nextURL);
}
async function fetchPage(url){
  loading=true;
  try{
    const r=await fetch(url,{headers:{'Accept':'application/json'},credentials:'include'});
    const j=await r.json().catch(()=>({}));
    const items=(Array.isArray(j)?j:(j.items||[])).filter(it=>{ const k=String(it.id); if(seenIds.has(k)) return false; seenIds.add(k); return true;});
    appendItems(items);
    parseNext(r);
  }catch(_){ setMoreVisible(false); }
  finally{ loading=false; }
}

// vistas robustas
function bumpView(art){
  const id=(art.getAttribute('data-id')||'').trim(); if(!id) return;
  const seen = new Set((JSON.parse(localStorage.getItem('seen_views')||'[]')||[]).slice(-500).map(String));
  if(seen.has(id)) return;
  seen.add(id); try{ localStorage.setItem('seen_views', JSON.stringify([...seen].slice(-500))); }catch(_){}
  (async()=>{
    try{
      const fp=(navigator.userAgent||'')+'|'+(navigator.language||'')+'|'+(Intl.DateTimeFormat().resolvedOptions().timeZone||'');
      const res=await fetch(`/api/notes/${id}/view`,{method:'POST',headers:{'X-FP':fp}});
      let j={}; try{ j=await res.json(); }catch(_){}
      const span=art.querySelector('.views');
      if(span){ const m=/(\d+)/.exec(span.textContent||'0'); const cur=m?parseInt(m[1],10):0; span.textContent='👁 '+(cur+1); }
    }catch(_){}
  })();
}
let __obs=null;
function attachObservers(){
  try{
    if(!__obs){
      __obs = new IntersectionObserver((entries)=>entries.forEach(en=>{ if(en.isIntersecting){ bumpView(en.target); __obs.unobserve(en.target); } }), {root:null, rootMargin:'0px 0px -20% 0px', threshold:0.25});
    }
    document.querySelectorAll('article.note[data-id]').forEach(el=>{ if(!el.dataset.observing){ el.dataset.observing='1'; __obs.observe(el);} });
  }catch(_){}
}

// nota única (URL ?id=123)
async function fetchOne(id){
  const r=await fetch(`/api/notes/${encodeURIComponent(id)}`,{headers:{'Accept':'application/json'}});
  const j=await r.json().catch(()=>null);
  if(!r.ok || !j || j.ok===false || !j.item){ throw new Error('not_found'); }
  return j.item;
}
function enterSingleMode(){
  // oculta composer si existe
  const composer = document.querySelector('form, #composer, .composer'); if(composer){ composer.style.display='none'; }
  setMoreVisible(false);
  // botón para volver al inicio
  if(!document.getElementById('p12-back-home')){
    const b=document.createElement('a'); b.id='p12-back-home'; b.textContent='← Volver al inicio'; b.href='/'; b.style.cssText='display:inline-block;margin:12px 16px;';
    (FEED.parentElement||document.body).insertBefore(b, FEED);
  }
}

window.addEventListener('DOMContentLoaded', ()=>{
  const singleId = Q.get('id');
  if(singleId){
    FEED.innerHTML='';
    enterSingleMode();
    fetchOne(singleId).then(it=>{
      appendItems([it]);
      const el=FEED.querySelector('article.note'); if(el) bumpView(el); // en nota única, sube vista inmediata
    }).catch(()=>{ FEED.innerHTML='<p style="margin:16px">Nota no encontrada.</p>'; });
  }else{
    fetchPage('/api/notes?limit=10');
  }
});
})();
</script>
<style>
#deploy-stamp-banner{display:none!important}
#msg{position:fixed;left:50%;transform:translateX(-50%);top:12px;z-index:9999;padding:.5rem .75rem;border-radius:8px;font:14px system-ui, sans-serif}
#msg.ok{background:#e6ffed;border:1px solid #98e4a3}
#msg.error{background:#ffe8e6;border:1px solid #ffb3a3}
#msg.hidden{display:none}
.hidden{display:none!important}
</style>
""".strip()

def patch_one(path: pathlib.Path):
    src = path.read_text(encoding='utf-8')
    bak = path.with_suffix(path.suffix + ".v6.bak")
    if not bak.exists():
        shutil.copyfile(path, bak)
    new = src
    # Reemplaza cualquier hotfix anterior (v4/v5/v6) o inserta antes de </body>.
    for hid in HOTFIX_IDS:
        new2 = re.sub(rf"<script[^>]+id=[\"']{hid}[\"'][\s\S]*?</script>", JS, new, flags=re.I)
        if new2 != new:
            new = new2
    if new == src:
        if re.search(r"</body\s*>", new, flags=re.I):
            new = re.sub(r"</body\s*>", JS+"\n</body>", new, flags=re.I)
        else:
            new = new + "\n" + JS
    path.write_text(new, encoding='utf-8')
    print(f"✓ patched {path}")

for f in FILES: patch_one(f)
