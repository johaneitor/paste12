#!/usr/bin/env python3
import re, sys, pathlib, shutil

FILES = [pathlib.Path(p) for p in (
    "backend/static/index.html",
    "frontend/index.html",
    "index.html",
) if pathlib.Path(p).exists()]

if not FILES:
    print("✗ No encontré ningún index.html para parchear"); sys.exit(0)

HOTFIX_ID_OLD = r'(?:p12-hotfix-v4)'
HOTFIX_ID_NEW = 'p12-hotfix-v5'

JS = r"""
<script id="p12-hotfix-v5">
(()=>{'use strict';
if (window.__P12_HOTFIX_V5__) return; window.__P12_HOTFIX_V5__=true;

// === util ===
const $=(s,c=document)=>c.querySelector(s);
const esc=s=>(s??'').toString().replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));

// Apaga SW/banners si ?nosw=1 o ?debug=1
const Q=new URLSearchParams(location.search);
if((Q.has('nosw')||Q.has('debug')) && 'serviceWorker' in navigator){
  try{navigator.serviceWorker.getRegistrations().then(rs=>rs.forEach(r=>r.unregister()));}catch(e){}
  try{if(caches&&caches.keys) caches.keys().then(ks=>ks.forEach(k=>caches.delete(k)));}catch(e){}
}
(function killBanners(){
  const BAD=[/nueva versión disponible/i,/actualiza para ver/i,/update available/i];
  for(const el of Array.from(document.body.querySelectorAll('*'))){
    const t=(el.textContent||'').trim(); if(!t) continue;
    if(BAD.some(rx=>rx.test(t))){
      try{ el.closest('[role="alert"],.toast,.snackbar,.banner')?.remove(); }catch(_){}
      try{ el.remove(); }catch(_){}
    }
  }
})();

// === contenedor único del feed ===
let FEED = document.querySelector('#list, .list, [data-notes], [data-feed], #notes, #feed');
if(!FEED){ FEED=document.createElement('section'); FEED.id='list'; (document.body||document.documentElement).append(FEED); }

// === flashes mínimos ===
function flash(ok,msg){
  let el = $('#msg'); if(!el){ el=document.createElement('div'); el.id='msg'; (document.body||document.documentElement).prepend(el); }
  el.className = ok?'ok':'error'; el.textContent = msg;
  setTimeout(()=>{ el.className='hidden'; el.textContent=''; }, 2000);
}

// === render unificado con spans .likes / .views
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
  const div=document.createElement('div');
  div.innerHTML = items.map(cardHTML).join('');
  FEED.append(...div.children);
}

// === delegación: like / ver más / compartir / reportar
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
      if (btnLike.disabled) return;
      btnLike.disabled = true;
      let j={};
      try{
        const r=await fetch(`/api/notes/${id}/like`,{
          method:'POST', credentials:'include',
          headers:{'Accept':'application/json'}
        });
        j = await r.json().catch(()=>({}));
      }catch(_){}
      const el = art.querySelector('.likes');
      if (el && typeof j.likes!=='undefined') el.textContent = '❤ '+j.likes;
      btnLike.disabled = false;
    }else if(btnMore){
      art.querySelector('.menu')?.classList.toggle('hidden');
    }else if(btnShare){
      const url = `${location.origin}/?id=${id}`;
      if(navigator.share){ await navigator.share({title:`Nota #${id}`, url}); }
      else { await navigator.clipboard.writeText(url); flash(true,'Link copiado'); }
      art.querySelector('.menu')?.classList.add('hidden');
    }else if(btnRpt){
      let j={};
      try{
        const r=await fetch(`/api/notes/${id}/report`,{
          method:'POST', credentials:'include',
          headers:{'Accept':'application/json'}
        });
        j=await r.json().catch(()=>({}));
      }catch(_){}
      if(j?.removed){ art.remove(); flash(true,'Nota eliminada'); }
      else { flash(true,'Reporte enviado'); }
      art.querySelector('.menu')?.classList.add('hidden');
    }else if(btnExp){
      const box=art.querySelector('[data-text]'); if(!box) return;
      const full=box.getAttribute('data-full')||'';
      const expanded = btnExp.getAttribute('data-expanded')==='1';
      if(expanded){ box.textContent = (full.length>180? full.slice(0,160)+'…' : full); btnExp.textContent='Ver más'; btnExp.setAttribute('data-expanded','0'); }
      else        { box.textContent = full; btnExp.textContent='Ver menos'; btnExp.setAttribute('data-expanded','1'); }
    }
  }catch(_){}
}, {capture:true});

// === publicar (valida ≥12 y fallback a form si JSON 400)
function pickTextarea(){ return document.querySelector('textarea[name=text], #text, textarea'); }
function pickTTL(){ return document.querySelector('input[name=ttl_hours], #ttl, select[name=ttl_hours], select'); }
function validateText(s){ return (s||'').trim().length >= 12; }
async function publish(ev){
  ev && ev.preventDefault && ev.preventDefault();
  const ta = pickTextarea(); const ttl = pickTTL();
  const text=(ta?.value||'').trim();
  if(!validateText(text)){ flash(false,'Escribí un poco más (≥ 12 caracteres).'); return; }
  const body={ text }; const v=parseInt(ttl?.value||'',10); if(Number.isFinite(v) && v>0) body.ttl_hours=v;

  let r=null, j=null;
  try{
    r=await fetch('/api/notes',{method:'POST',credentials:'include',
      headers:{'Content-Type':'application/json','Accept':'application/json'},
      body:JSON.stringify(body)
    });
  }catch(_){}
  // fallback form
  if(!r || !r.ok){
    const fd = new URLSearchParams(); fd.set('text', text); if(body.ttl_hours) fd.set('ttl_hours', String(body.ttl_hours));
    try{
      r=await fetch('/api/notes',{method:'POST',credentials:'include',
        headers:{'Content-Type':'application/x-www-form-urlencoded','Accept':'application/json'},
        body:fd
      });
    }catch(_){}
  }
  try{ j=await r.json(); }catch(_){ j=null; }
  if(!r || !r.ok || !j || j.ok===false){ flash(false,(j&&j.error)||('Error HTTP '+(r&&r.status))); return; }

  const it = j.item || {id:j.id, text, likes:j.likes||0, views:0, timestamp:new Date().toISOString()};
  const wrap=document.createElement('div'); wrap.innerHTML=cardHTML(it);
  FEED.prepend(wrap.firstElementChild);
  if(ta) ta.value=''; if(ttl) ttl.value='';
  flash(true,'Publicado ✅');
}
window.addEventListener('DOMContentLoaded', ()=>{
  const btn = document.getElementById('send'); if(btn){ btn.addEventListener('click', publish, {capture:true}); }
  const ta  = pickTextarea(); if(ta){ ta.addEventListener('keydown',(e)=>{ if(e.key==='Enter'&&(e.ctrlKey||e.metaKey)) publish(e);}); }
});

// === paginación keyset
let nextURL=null, loading=false, seen=new Set();
function setMoreVisible(v){
  let b=document.getElementById('p12-more'); if(!b){
    b=document.createElement('button'); b.id='p12-more'; b.type='button';
    b.textContent='Cargar más';
    b.style.cssText='display:block;margin:12px auto;padding:.6rem 1rem;border-radius:999px;border:1px solid #e5e7eb;background:#fff;';
    FEED.after(b);
    b.onclick=()=>{ if(nextURL && !loading) fetchPage(nextURL); };
  }
  b.style.display = v ? '' : 'none';
}
function parseNext(res){
  nextURL=null;
  const link = res.headers.get('Link') || res.headers.get('link');
  if(link){ const m=/<([^>]+)>;\s*rel="?next"?/i.exec(link); if(m) nextURL=m[1]; }
  if(!nextURL){
    try{
      const xn = JSON.parse(res.headers.get('X-Next-Cursor')||'null');
      if(xn && xn.cursor_ts && xn.cursor_id){
        nextURL = `/api/notes?cursor_ts=${encodeURIComponent(xn.cursor_ts)}&cursor_id=${xn.cursor_id}`;
      }
    }catch(_){}
  }
  setMoreVisible(!!nextURL);
}
async function fetchPage(url){
  loading=true;
  try{
    const r=await fetch(url,{headers:{'Accept':'application/json'},credentials:'include'});
    const j=await r.json().catch(()=>({}));
    const items=(Array.isArray(j)?j:(j.items||[])).filter(it=>{ const k=String(it.id); if(seen.has(k)) return false; seen.add(k); return true;});
    appendItems(items);
    parseNext(r);
  }catch(_){ setMoreVisible(false); }
  finally{ loading=false; }
}
window.addEventListener('DOMContentLoaded', ()=>{ fetchPage('/api/notes?limit=10'); });

// === observer de vistas (funciona con <span class="views">)
(function(){
  try{
    const seen = new Set((JSON.parse(localStorage.getItem('seen_views')||'[]')||[]).slice(-500).map(String));
    const save = ()=>{ try{ localStorage.setItem('seen_views', JSON.stringify([...seen].slice(-500))); }catch(_){} };
    const fp = (navigator.userAgent||'')+'|'+(navigator.language||'')+'|'+(Intl.DateTimeFormat().resolvedOptions().timeZone||'');
    const obs = new IntersectionObserver((entries)=>{
      entries.forEach(async (entry)=>{
        if (!entry.isIntersecting) return;
        const art = entry.target;
        const id  = (art.getAttribute('data-id')||'').trim();
        if (!id || seen.has(id)) { obs.unobserve(art); return; }
        seen.add(id); save();
        try{
          const res = await fetch(`/api/notes/${id}/view`, {method:'POST', headers:{'X-FP': fp}});
          let j={}; try{ j=await res.json(); }catch(_){}
          const v = art.querySelector('.views');
          if(v && (res.ok && (j.ok || j.id))){
            const m=/(\d+)/.exec(v.textContent||'0'); const cur=m?parseInt(m[1],10):0;
            v.textContent = '👁 '+(cur+1);
          }
        }catch(_){}
        obs.unobserve(art);
      });
    }, {root:null, threshold:.6});
    function attach(){ document.querySelectorAll('article.note[data-id]').forEach(el=>{ if(!el.dataset.observing){ el.dataset.observing='1'; obs.observe(el);} }); }
    const mo=new MutationObserver(attach); mo.observe(document.body,{childList:true,subtree:true});
    attach();
  }catch(_){}
})();
})();
</script>
<style>/* oculta banners SW de versión */#deploy-stamp-banner{display:none!important}</style>
""".strip()

def patch_one(path: pathlib.Path):
    src = path.read_text(encoding='utf-8')
    bak = path.with_suffix(path.suffix + ".likes_views_fix_v5.bak")
    if not bak.exists():
        bak.write_text(src, encoding='utf-8')

    # si hay v4, lo reemplazamos entero; si hay otra versión previa v5, la sustituimos; si no hay, lo insertamos antes de </body>
    new = re.sub(rf"<script[^>]+id=[\"']{HOTFIX_ID_OLD}[\"'][\s\S]*?</script>", JS, src, flags=re.I)
    if new == src:
        new = re.sub(rf"<script[^>]+id=[\"']p12-hotfix-v5[\"'][\s\S]*?</script>", JS, new, flags=re.I)
    if new == src:
        # insertar antes de </body>
        if re.search(r"</body\s*>", new, flags=re.I):
            new = re.sub(r"</body\s*>", JS+"\n</body>", new, flags=re.I)
        else:
            new = new + "\n" + JS

    path.write_text(new, encoding='utf-8')
    print(f"✓ patched {path}")

for f in FILES:
    patch_one(f)
