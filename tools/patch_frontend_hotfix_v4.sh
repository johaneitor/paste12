#!/usr/bin/env bash
set -euo pipefail

TS="$(date -u +%Y%m%d-%H%M%SZ)"
edit_one() {
  local F="$1"
  [ -f "$F" ] || return 0
  local BAK="${F}.hotfix_v4.${TS}.bak"
  cp -f "$F" "$BAK"

  # 1) Elimina bloques de shims/clientes previos conocidos (no rompe si no están)
  awk '
    BEGIN{skip=0}
    /MINI-CLIENT v3\.1 START/ {skip=1}
    /MINI-CLIENT v3\.1 END/   {skip=0; next}
    /MINI-SHIM v3\.3 START/   {skip=1}
    /MINI-SHIM v3\.3 END/     {skip=0; next}
    /COHESION-SHIM START/     {skip=1}
    /COHESION-SHIM END/       {skip=0; next}
    /hotfix-client-v1/        {next}          # bloque simple
    /script id="p12-client-template"/, /<\/script>/ {next} # bloque template
    { if(!skip) print $0 }
  ' "$BAK" > "$F.tmp1"

  # 2) Inserta hotfix v4 (idempotente) antes de </body>
  cat > "$F.hotfix.js" <<'JS'
<script id="p12-hotfix-v4">
(()=>{'use strict';
if (window.__P12_HOTFIX_V4__) return; window.__P12_HOTFIX_V4__=true;

const Q=new URLSearchParams(location.search);

// Apaga SW/banners si ?nosw=1 o ?debug=1
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

// ==== Helpers
const $=(s,c=document)=>c.querySelector(s);
const $$=(s,c=document)=>Array.from(c.querySelectorAll(s));
const esc=s=>(s??'').toString().replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));

// ==== Feed unificado
const FEED_SEL = '#list, .list, [data-notes], [data-feed], #notes, #feed';
let FEED = $(FEED_SEL);
if(!FEED){ FEED = document.createElement('section'); FEED.id='list'; (document.body||document.documentElement).appendChild(FEED); }

// ==== Flash
function flash(ok,msg){
  let el = $('#msg'); if(!el){ el=document.createElement('div'); el.id='msg'; (document.body||document.documentElement).prepend(el); }
  el.className = ok?'ok':'error'; el.textContent = msg;
  setTimeout(()=>{ el.className='hidden'; el.textContent=''; }, 2200);
}

// ==== Render
function cardHTML(it){
  const txt = it.text || it.content || it.summary || '';
  let short = txt, needMore=false;
  if (txt.length > 180){ short = txt.slice(0,160)+'…'; needMore=true; }
  return `
    <article class="note" data-id="${it.id}">
      <div data-text="1" data-full="${esc(txt)}">${esc(short)||'(sin texto)'}</div>
      <div class="meta">#${it.id} · ❤ ${it.likes??0} · 👁 ${it.views??0}
        <button class="act like" type="button">❤</button>
        <button class="act more" type="button">⋯</button>
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
  const div=document.createElement('div');
  div.innerHTML = items.map(cardHTML).join('');
  FEED.append(...div.children);
}

// ==== Acciones delegadas (like/⋯/share/report/ver más)
document.addEventListener('click', async (e)=>{
  const art  = e.target.closest && e.target.closest('article.note');
  const id   = art && art.getAttribute('data-id');
  if(!art || !id) return;

  const like = e.target.closest('button.like');
  const more = e.target.closest('button.more');
  const share= e.target.closest('button.share');
  const rpt  = e.target.closest('button.report');
  const exp  = e.target.closest('button.expand');

  try{
    if(like){
      const r=await fetch(`/api/notes/${id}/like`,{method:'POST',credentials:'include'});
      const j=await r.json().catch(()=>({}));
      if(j && typeof j.likes!=='undefined'){
        const m=art.querySelector('.meta');
        if(m) m.innerHTML = m.innerHTML.replace(/❤\s*\d+/, '❤ '+j.likes);
      }
    }else if(more){
      art.querySelector('.menu')?.classList.toggle('hidden');
    }else if(share){
      const url = `${location.origin}/?id=${id}`;
      if(navigator.share){ await navigator.share({title:`Nota #${id}`, url}); }
      else { await navigator.clipboard.writeText(url); flash(true,'Link copiado'); }
      art.querySelector('.menu')?.classList.add('hidden');
    }else if(rpt){
      const r=await fetch(`/api/notes/${id}/report`,{method:'POST',credentials:'include'});
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

// ==== Publicar (JSON con ttl_hours + fallback FORM)
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
  try{ r=await fetch('/api/notes',{method:'POST',credentials:'include',headers:{'Content-Type':'application/json','Accept':'application/json'},body:JSON.stringify(body)}); }catch(_){}
  if(!r || !r.ok){
    const fd = new URLSearchParams(); fd.set('text', text); if(body.ttl_hours) fd.set('ttl_hours', String(body.ttl_hours));
    try{ r=await fetch('/api/notes',{method:'POST',credentials:'include',headers:{'Content-Type':'application/x-www-form-urlencoded','Accept':'application/json'},body:fd}); }catch(_){}
  }
  try{ j=await r.json(); }catch(_){ j=null; }
  if(!r || !r.ok || !j || j.ok===false){ flash(false,(j&&j.error)||('Error HTTP '+(r&&r.status))); return; }

  // Prepend nuevo item
  const it = j.item || {id:j.id, text, likes:j.likes||0, views:0, timestamp:new Date().toISOString()};
  const wrap=document.createElement('div'); wrap.innerHTML=cardHTML(it);
  FEED.prepend(wrap.firstElementChild);
  if(ta) ta.value=''; if(ttl) ttl.value='';
  flash(true,'Publicado ✅');
}

// Bindeo de publicar (click + Ctrl/Cmd+Enter)
window.addEventListener('DOMContentLoaded', ()=>{
  const btn = document.getElementById('send'); if(btn){ btn.addEventListener('click', publish, {capture:true}); }
  const ta  = pickTextarea(); if(ta){ ta.addEventListener('keydown',(e)=>{ if(e.key==='Enter'&&(e.ctrlKey||e.metaKey)) publish(e);}); }
});

// ==== Paginación keyset (Link / X-Next-Cursor) + botón único
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
    const r=await fetch(url,{headers:{'Accept':'application/json'},credentials:'include'});
    const j=await r.json().catch(()=>({}));
    const items=(Array.isArray(j)?j:(j.items||[])).filter(it=>!seen.has(String(it.id)));
    items.forEach(it=>seen.add(String(it.id)));
    appendItems(items);
    parseNext(r);
  }catch(_){
    // en error ocultamos el botón para no confundir
    setMoreVisible(false);
  }finally{ loading=false; }
}

// Arranque: pag1
window.addEventListener('DOMContentLoaded', ()=>{ fetchPage('/api/notes?limit=10'); });
})();
</script>
<style>/* oculta banners SW de versión */#deploy-stamp-banner{display:none!important}</style>
JS

  # Inserta el bloque justo antes de </body>
  awk -v ins="$(sed 's:[:\\/&]:\\&:g' "$F.hotfix.js")" '
    BEGIN{done=0}
    /<\/body>/ && !done {print ins; print; done=1; next}
    {print}
    END{if(!done) print ins}
  ' "$F.tmp1" > "$F"

  rm -f "$F.tmp1" "$F.hotfix.js"
  echo "✓ patched $F  (backup: $BAK)"
}

# Aplica sobre posibles ubicaciones del index
edit_one backend/static/index.html
edit_one frontend/index.html
edit_one index.html || true
