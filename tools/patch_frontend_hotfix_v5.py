#!/usr/bin/env python3
import re, sys, pathlib, shutil

CANDS = [pathlib.Path("backend/static/index.html"), pathlib.Path("frontend/index.html"), pathlib.Path("index.html")]

HOTFIX = r"""
<!-- P12 HOTFIX v5 -->
<script id="p12-hotfix-v5">
(()=>{'use strict';
if (window.__P12_HOTFIX_V5__) return; window.__P12_HOTFIX_V5__=true;

const Q = new URLSearchParams(location.search);

// ==== API base (para mini backends) ====
const API_BASE =
  (Q.get('api')?.replace(/\/+$/,'') || window.API_BASE || '').trim() || '';
const api = (p) => {
  if (/^https?:\/\//i.test(p)) return p;
  const base = API_BASE || '';
  return base + (p.startsWith('/api/') ? p : (p.startsWith('/')? p : '/api/'+p));
};

// ==== Apaga SW + banners si se pide ====
if ((Q.has('nosw')||Q.has('debug')) && 'serviceWorker' in navigator){
  try{navigator.serviceWorker.getRegistrations().then(rs=>rs.forEach(r=>r.unregister()));}catch(e){}
  try{if (window.caches && caches.keys) caches.keys().then(ks=>ks.forEach(k=>caches.delete(k)));}catch(e){}
}
// matar banners de “nueva actualización”
(function(){
  const BAD=[/nueva versión disponible/i,/actualiza para ver/i,/update available/i];
  for(const el of Array.from(document.body.querySelectorAll('*'))){
    const t=(el.textContent||'').trim(); if(!t) continue;
    if(BAD.some(rx=>rx.test(t))){
      try{ el.closest('[role="alert"],.toast,.snackbar,.banner')?.remove(); }catch(_){}
      try{ el.remove(); }catch(_){}
    }
  }
})();

// ==== Feed y rendering ====
const $=(s,c=document)=>c.querySelector(s);
const FEED = $('#list,.list,[data-feed],#feed') || (()=>{
  const s = document.createElement('section'); s.id='list';
  (document.body||document.documentElement).appendChild(s); return s;
})();

const esc = s => (s??'').toString().replace(/[&<>"]/g, c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));
function cardHTML(it){
  const txt = it.text || it.content || it.summary || '';
  let short = txt, needMore=false;
  if (txt.length > 180){ short = txt.slice(0,160)+'…'; needMore=true; }
  return `
    <article class="note" data-id="${it.id}">
      <div data-text="1" data-full="${esc(txt)}">${esc(short) || '(sin texto)'}</div>
      <div class="meta">#${it.id} · ❤ ${it.likes??0} · <span class="views">👁 ${it.views??0}</span>
        <button class="act like" type="button" aria-label="Me gusta">❤</button>
        <button class="act more" type="button" aria-label="Opciones">⋯</button>
      </div>
      <div class="menu hidden">
        ${needMore?'<button class="expand" type="button">Ver más</button>':''}
        <button class="share"  type="button">Compartir</button>
        <button class="report" type="button">Reportar 🚩</button>
      </div>
    </article>`;
}
function appendItems(items){
  if(!items||!items.length) return;
  const div=document.createElement('div'); div.innerHTML = items.map(cardHTML).join('');
  FEED.append(...div.children);
}

// ==== Acciones delegadas ====
document.addEventListener('click', async (e)=>{
  const art = e.target.closest && e.target.closest('article.note');
  const id  = art && art.getAttribute('data-id');
  if(!art || !id) return;
  const like = e.target.closest('button.like');
  const more = e.target.closest('button.more');
  const share= e.target.closest('button.share');
  const rpt  = e.target.closest('button.report');
  const exp  = e.target.closest('button.expand');

  try{
    if(like){
      const r=await fetch(api(`/api/notes/${id}/like`),{method:'POST',credentials:'include'});
      const j=await r.json().catch(()=>({}));
      if (j && typeof j.likes!=='undefined'){
        const meta=art.querySelector('.meta');
        if(meta){ meta.innerHTML = meta.innerHTML.replace(/❤\s*\d+/, '❤ '+j.likes); }
      }
    }else if(more){
      art.querySelector('.menu')?.classList.toggle('hidden');
    }else if(share){
      const url = `${location.origin}/?id=${encodeURIComponent(id)}${API_BASE?('&api='+encodeURIComponent(API_BASE)):""}`;
      if(navigator.share){ try{ await navigator.share({title:`Nota #${id}`, url}); }catch(_){} }
      else { try{ await navigator.clipboard.writeText(url); }catch(_){} }
      art.querySelector('.menu')?.classList.add('hidden');
    }else if(rpt){
      const r=await fetch(api(`/api/notes/${id}/report`),{method:'POST',credentials:'include'});
      const j=await r.json().catch(()=>({}));
      if(j?.removed){ art.remove(); flash(true,'Nota eliminada'); }
      else { flash(true,'Reporte enviado'); }
      art.querySelector('.menu')?.classList.add('hidden');
    }else if(exp){
      const box=art.querySelector('[data-text]'); if(!box) return;
      const full=box.getAttribute('data-full')||'';
      const expanded = exp.getAttribute('data-expanded')==='1';
      if(expanded){ box.textContent = (full.length>180? full.slice(0,160)+'…' : full); exp.textContent='Ver más'; exp.setAttribute('data-expanded','0'); }
      else        { box.textContent = full; exp.textContent='Ver menos'; exp.setAttribute('data-expanded','1'); }
    }
  }catch(_){}
}, {capture:true});

// ==== Flash (mensajes) ====
function flash(ok,msg){
  let el = document.getElementById('msg');
  if(!el){ el=document.createElement('div'); el.id='msg'; (document.body||document.documentElement).prepend(el); }
  el.className = ok?'ok':'error'; el.textContent = msg;
  setTimeout(()=>{ el.className='hidden'; el.textContent=''; }, 2200);
}

// ==== Publicar (JSON + FORM fallback) ====
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
    r=await fetch(api('/api/notes'),{method:'POST',credentials:'include',headers:{'Content-Type':'application/json','Accept':'application/json'},body:JSON.stringify(body)});
  }catch(_){}
  if(!r || !r.ok){
    const fd = new URLSearchParams(); fd.set('text', text); if(body.ttl_hours) fd.set('ttl_hours', String(body.ttl_hours));
    try{
      r=await fetch(api('/api/notes'),{method:'POST',credentials:'include',headers:{'Content-Type':'application/x-www-form-urlencoded','Accept':'application/json'},body:fd});
    }catch(_){}
  }
  try{ j=await r.json(); }catch(_){}
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

// ==== Paginación (Link / X-Next-Cursor) ====
let nextURL=null, loading=false, seen=new Set(Array.from(document.querySelectorAll('article.note[data-id]')).map(x=>x.getAttribute('data-id')));
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
  if(link){
    const m=/<([^>]+)>;\s*rel="?next"?/i.exec(link); if(m) nextURL=m[1];
  }
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
    const r=await fetch(api(url),{headers:{'Accept':'application/json'},credentials:'include'});
    const j=await r.json().catch(()=>({}));
    const items=(Array.isArray(j)?j:(j.items||[])).filter(it=>!seen.has(String(it.id)));
    items.forEach(it=>seen.add(String(it.id)));
    appendItems(items);
    parseNext(r);
  }catch(_){ setMoreVisible(false); }
  finally{ loading=false; }
}

// ==== Single-note route (?id=xxx) ====
async function showSingle(id){
  try{
    const r=await fetch(api(`/api/notes/${encodeURIComponent(id)}`),{headers:{'Accept':'application/json'},credentials:'include'});
    const j=await r.json().catch(()=>({}));
    const it=j&&j.item;
    const root = FEED;
    if(it){
      root.innerHTML = (function(){ const d=document.createElement('div'); d.innerHTML=cardHTML(it); return d.innerHTML; })();
      document.title = `Nota #${it.id} – Paste12`;
      document.documentElement.setAttribute('data-single','1');
      const meta = document.createElement('meta'); meta.name='p12-single'; meta.content='1'; document.head.appendChild(meta);
      const back=document.createElement('a'); back.href='/'; back.textContent='← Volver al feed';
      back.className='btn'; back.style.margin='12px auto'; root.after(back);
    }else{
      root.innerHTML = '<article class="note"><div>(Nota no encontrada)</div></article>';
    }
  }catch(_){}
}
window.addEventListener('DOMContentLoaded', ()=>{
  const pid = Q.get('id');
  if(pid){ showSingle(pid); return; }
  fetchPage('/api/notes?limit=10');
});

// ==== View observer robusto ====
(function(){
  try{
    const seen = new Set();
    try{ (JSON.parse(localStorage.getItem('seen_views')||'[]')||[]).slice(-500).forEach(id=>seen.add(String(id))); }catch(_){}
    const save = ()=>{ try{ localStorage.setItem('seen_views', JSON.stringify([...seen].slice(-500))); }catch(_){} };

    const postView = async (id, el)=>{
      if(!id || seen.has(id)) return;
      seen.add(id); save();
      try{
        const r=await fetch(api(`/api/notes/${id}/view`),{method:'POST',credentials:'include'});
        const j=await r.json().catch(()=>({}));
        if (r.ok && (j.ok || j.id)){
          const span = el.querySelector('.views');
          if(span){
            const m = /(\d+)/.exec(span.textContent||'0'); const cur = m?parseInt(m[1],10):0;
            span.textContent = '👁 ' + (cur+1);
          }
        }
      }catch(_){}
    };

    if ('IntersectionObserver' in window){
      const obs = new IntersectionObserver((entries)=>{
        entries.forEach((entry)=>{
          if (!entry.isIntersecting) return;
          const el = entry.target; const id = (el.getAttribute('data-id')||'').trim();
          postView(id, el);
          try{ obs.unobserve(el); }catch(_){}
        });
      }, {root:null, threshold:0.3});
      const attach=()=>{ document.querySelectorAll('article.note[data-id]').forEach(el=>{ if(!el.dataset.observing){ el.dataset.observing='1'; obs.observe(el); } }); };
      const list = FEED; if(list){ new MutationObserver(attach).observe(list,{childList:true}); }
      attach();
    }else{
      // Fallback: primer paint marca vistas
      document.querySelectorAll('article.note[data-id]').forEach(el=>postView(el.getAttribute('data-id')||'', el));
    }
  }catch(_){}
})();
})();
</script>
<style>/* oculta banners SW/version */#deploy-stamp-banner{display:none!important}</style>
"""

def patch(f: pathlib.Path):
    if not f.exists(): return False, "skip"
    html = f.read_text(encoding="utf-8")
    orig = html

    # 1) eliminar cualquier <script> que contenga <!doctype html ...> (bloque intruso)
    html = re.sub(r"<script[^>]*>\\s*<!doctype\\s+html[\\s\\S]*?</script>", "", html, flags=re.I)

    # 2) inyectar hotfix v5 antes de </body>
    if "id=\"p12-hotfix-v5\"" not in html:
        html = re.sub(r"</body\\s*>", HOTFIX + "\\n</body>", html, flags=re.I)

    if html == orig:
        return False, "no-change"
    bak = f.with_suffix(f.suffix + ".p12_hotfix_v5.bak")
    if not bak.exists():
        shutil.copyfile(f, bak)
    f.write_text(html, encoding="utf-8")
    return True, f"patched | backup={bak.name}"

did = []
for p in CANDS:
    ok, msg = patch(p)
    if ok or msg!="skip":
        did.append((p, msg))

if not did:
    print("✗ No encontré index.html en rutas conocidas"); sys.exit(1)
for p,msg in did:
    print(f"{p}: {msg}")
