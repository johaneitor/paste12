#!/usr/bin/env bash
set -euo pipefail
# Parche idempotente: inyecta/actualiza un bloque <script> con lógica de:
# - Publish con fallback (JSON -> FORM)
# - Delegación de eventos (like, report, share) también para "Ver más"
# - Vistas con IntersectionObserver (un ping por nota visible)
# - Modo nota única (?id=) que muestra sólo la tarjeta + botón "Volver"
# - Opcional: desregistro SW cuando ?nosw=1
TGT=""
for f in backend/static/index.html frontend/index.html; do
  [ -f "$f" ] && TGT="$f"
done
[ -n "$TGT" ] || { echo "✗ No encontré index.html"; exit 2; }

HTML="$(cat "$TGT")"
MARK="P12 COHESION V7"
if grep -q "$MARK" "$TGT"; then
  echo "OK: v7 ya presente (no se duplica)"; exit 0
fi

read -r -d '' JS <<'JSEND'
<!-- === P12 COHESION V7 (idempotente) === -->
<script id="p12-cohesion-v7">
(()=>{ 'use strict';
if (window.__P12_V7__) return; window.__P12_V7__=true;

const Q = new URLSearchParams(location.search);
if (Q.has('nosw') && 'serviceWorker' in navigator) {
  try { navigator.serviceWorker.getRegistrations().then(rs=>rs.forEach(r=>r.unregister())); } catch(_){}
}

// Helpers
const FEED = document.querySelector('#feed') || document.body;
const seen = new Set();
const once = (fn)=>{ let done=false; return (...a)=>{ if(!done){ done=true; try{fn(...a);}catch(_){}}}; };
const api = (u,opt={})=>fetch(u, Object.assign({credentials:'include'}, opt));
const cardHTML = (it)=>{
  const txt = (it.text || it.summary || '').replace(/[<>]/g, s=>({ '<':'&lt;','>':'&gt;' }[s]));
  return `
  <article class="note" data-id="${it.id}">
    <div class="note-body">${txt}</div>
    <div class="note-acts">
      <button data-act="like">👍 <span class="k-like">${it.likes||0}</span></button>
      <button data-act="share">🔗 Compartir</button>
      <button data-act="report">🚩 Reportar</button>
      <span class="k-view">👁️ ${it.views||0}</span>
    </div>
  </article>`;
};

// Publicar con fallback: JSON -> FORM
const publish = async (text)=>{
  text = (text||'').trim();
  // 1) JSON (si backend lo acepta, genial; si devuelve 4xx, cae a FORM)
  try{
    const r = await api('/api/notes', {
      method:'POST',
      headers:{'Content-Type':'application/json'},
      body: JSON.stringify({text})
    });
    if (r.ok) return r.json();
  }catch(_){}
  // 2) FORM urlencoded (super compatible)
  const body = new URLSearchParams({text});
  const r2 = await api('/api/notes', {
    method:'POST',
    headers:{'Content-Type':'application/x-www-form-urlencoded'},
    body
  });
  return r2.json();
};

// “Ver más” + parseo de Link
let nextURL = null, loading=false;
const setMore = (show)=>{ const b=document.querySelector('#more'); if(b){ b.style.display = show?'block':'none'; } };
const parseNext = (resp)=>{
  try{
    const link = resp.headers.get('Link')||'';
    const m = link.match(/<([^>]+)>;\\s*rel="next"/i);
    nextURL = m ? m[1] : null;
    setMore(!!nextURL);
  }catch(_){ nextURL=null; setMore(false); }
};
const appendItems = (items)=>{
  const frag = document.createDocumentFragment();
  items.forEach(it=>{
    if (seen.has(String(it.id))) return;
    seen.add(String(it.id));
    const wrap = document.createElement('div');
    wrap.innerHTML = cardHTML(it);
    frag.appendChild(wrap.firstElementChild);
  });
  FEED.appendChild(frag);
  // activar observadores de vista
  bootViews();
};
const fetchPage = async (url)=>{
  if (loading) return; loading=true;
  try{
    const r = await api(url, {headers:{'Accept':'application/json'}});
    const j = await r.json().catch(()=>({}));
    const items = (Array.isArray(j)?j:(j.items||[]));
    appendItems(items);
    parseNext(r);
  }catch(_){ setMore(false); } finally { loading=false; }
};

// Delegación de eventos (like/report/share) que funciona también tras “Ver más”
FEED.addEventListener('click', async (ev)=>{
  const btn = ev.target.closest('button[data-act]');
  if (!btn) return;
  const art = ev.target.closest('article.note'); if (!art) return;
  const id = art.getAttribute('data-id'); if (!id) return;
  const act = btn.getAttribute('data-act');
  try{
    if (act === 'like'){
      const r = await api(`/api/notes/${id}/like`, {method:'POST'});
      const j = await r.json().catch(()=>({}));
      const k = art.querySelector('.k-like'); if (k && j && typeof j.likes==='number') k.textContent = j.likes;
    } else if (act === 'report'){
      await api(`/api/notes/${id}/report`, {method:'POST'});
      btn.textContent = '🚩 Reportado';
    } else if (act === 'share'){
      const url = `${location.origin}/?id=${encodeURIComponent(id)}`;
      try{
        await navigator.clipboard.writeText(url);
        btn.textContent = '✅ Copiado';
      }catch(_){
        location.href = url; // fallback: ir a vista de nota única
      }
    }
  }catch(_){}
});

// Conteo de vistas: una por nota cuando entra al viewport (≈1s visible)
let io=null; const bootViews = once(()=>{ try{
  io = new IntersectionObserver((entries)=>{
    entries.forEach(async e=>{
      const el = e.target; if (!e.isIntersecting) return;
      if (el.__viewSent) return; // una sola vez
      el.__viewSent = true;
      const id = el.getAttribute('data-id'); if (!id) return;
      try{
        const r = await api(`/api/notes/${id}/view`, {method:'POST'});
        const j = await r.json().catch(()=>({}));
        const v = el.querySelector('.k-view');
        if (v && j && typeof j.views==='number') v.textContent = `👁️ ${j.views}`;
      }catch(_){}
    });
  }, {threshold:0.5});
  document.querySelectorAll('article.note').forEach(n=>io.observe(n));
} catch(_){ /* si no hay IO, no rompemos */ }});
const bootViewsReattach = ()=>{ if (!io) return; document.querySelectorAll('article.note').forEach(n=>io.observe(n)); };
const bootViews = ()=>{ // redefine para re-enganchar tras append
  try{
    if (!io) {
      io = new IntersectionObserver((entries)=>{
        entries.forEach(async e=>{
          const el=e.target; if (!e.isIntersecting || el.__viewSent) return;
          el.__viewSent = true;
          const id=el.getAttribute('data-id'); if (!id) return;
          try{
            const r=await api(`/api/notes/${id}/view`, {method:'POST'});
            const j=await r.json().catch(()=>({}));
            const v=el.querySelector('.k-view');
            if (v && j && typeof j.views==='number') v.textContent = `👁️ ${j.views}`;
          }catch(_){}
        });
      }, {threshold:0.5});
    }
    document.querySelectorAll('article.note').forEach(n=>io.observe(n));
  }catch(_){}
};

// Modo nota única (?id=123): reemplaza feed por una sola tarjeta y agrega “Volver”
window.addEventListener('DOMContentLoaded', ()=>{
  const id = Q.get('id');
  if (id){
    (async()=>{
      try{
        const r = await api(`/api/notes/${encodeURIComponent(id)}`, {headers:{'Accept':'application/json'}});
        const j = await r.json().catch(()=>({}));
        const it = j && j.item;
        if (it){
          FEED.innerHTML = cardHTML(it);
          document.title = `Nota #${it.id} – Paste12`;
          // flags para herramientas/smokes
          try{
            document.documentElement.setAttribute('data-single-note','1');
            const m=document.createElement('meta'); m.name='p12-single'; m.content='1'; document.head.appendChild(m);
          }catch(_){}
          bootViews();
        }else{
          FEED.innerHTML = '<article class="note"><div>(Nota no encontrada)</div></article>';
        }
        const back=document.createElement('a'); back.href='/'; back.textContent='← Volver al feed';
        back.className='btn'; back.style.margin='12px auto'; FEED.after(back);
      }catch(_){}
    })();
    return; // no cargar feed
  }
  // Arranque normal: 1ª página + botón “Ver más”
  fetchPage('/api/notes?limit=10');
  const more = document.querySelector('#more');
  if (more) more.onclick = ()=>{ if(nextURL) fetchPage(nextURL); };
});
})();
</script>
<!-- === /P12 COHESION V7 === -->
JSEND

# Insertamos antes de </body>
NEW="$(printf '%s\n%s\n' "$HTML" "$JS")"
printf '%s' "$NEW" > "$TGT"
echo "patched: $TGT con bloque \"$MARK\""
