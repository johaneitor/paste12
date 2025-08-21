#!/usr/bin/env bash
set -Eeuo pipefail

echo "🔧 Reactivar TODO (front + features) — $(date)"

# --- 1) index.html minimal + AdSense + app.js ---
ih="frontend/index.html"
mkdir -p frontend/js frontend/css frontend/img
cp -f "$ih" "$ih.bak.$(date +%s)" 2>/dev/null || true

cat > "$ih" <<'HTML'
<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>Paste12</title>
  <link rel="preload" as="style" href="/css/styles.css">
  <link rel="stylesheet" href="/css/styles.css">
  <!-- AdSense (configura tu client) -->
  <script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=" crossorigin="anonymous"></script>
</head>
<body>
  <main id="app">
    <h1>Paste12</h1>
    <form id="new-note" class="composer">
      <textarea name="text" rows="3" placeholder="Escribe algo…"></textarea>
      <div class="actions">
        <button type="submit">Publicar</button>
        <small id="limit-hint"></small>
      </div>
    </form>
    <div id="feed"></div>
  </main>
  <script src="/js/app.js?v=$(date +%s)" defer></script>
</body>
</html>
HTML

# --- 2) app.js “full” con todo reactivado (likes, views, report, share, ads, paging, dedupe) ---
aj="frontend/js/app.js"
cp -f "$aj" "$aj.bak.$(date +%s)" 2>/dev/null || true
cat > "$aj" <<'JS'
(function(){
  // ===== STATE =====
  const state = {
    page: 1,
    hasMore: true,
    loading: false,
    rendered: new Set(),          // notas ya renderizadas (dedupe duro)
    viewed: sessionBackedSet('p12_viewed_once'), // vistas enviadas en esta sesión
    ioFeed: null,
    ioView: null
  };

  function sessionBackedSet(key){
    const raw = sessionStorage.getItem(key);
    const set = new Set(raw ? JSON.parse(raw) : []);
    const save = ()=> sessionStorage.setItem(key, JSON.stringify(Array.from(set)));
    return { has: (v)=>set.has(v), add:(v)=>{ set.add(v); save(); }, clear: ()=>{ set.clear(); save(); } };
  }

  // ===== DOM helpers =====
  const $ = (sel, root=document)=> root.querySelector(sel);
  const $$ = (sel, root=document)=> Array.from(root.querySelectorAll(sel));
  function el(tag, cls){ const e=document.createElement(tag); if(cls) e.className=cls; return e; }

  function ensureList(){
    let list = $('#feed');
    if (!list){ list = el('div','feed'); list.id='feed'; document.body.appendChild(list); }
    return list;
  }
  function ensureSentinel(list){
    let s = $('#sentinel');
    if (!s){ s = el('div'); s.id='sentinel'; s.style.height='1px'; list.appendChild(s); }
    else if(!s.parentNode){ list.appendChild(s); }
    return s;
  }

  // ===== UI: tarjeta =====
  function cardFor(n){
    const card = el('div','note-card'); card.dataset.id = n.id;

    const actions = el('div','note-actions');
    const menuBtn = el('button','menu-btn'); menuBtn.textContent = '⋮'; menuBtn.title = 'Opciones';
    const menu = el('div','menu'); menu.hidden = true;
    const reportBtn = el('button','menu-item'); reportBtn.textContent='🚩 Reportar';
    const shareBtn  = el('button','menu-item'); shareBtn.textContent='🔗 Compartir';
    menu.append(reportBtn, shareBtn);
    actions.append(menuBtn, menu);

    const text = el('div','note-text'); text.textContent = n.text || '';
    const meta = el('div','note-meta');

    const likeBtn = el('button','like-btn'); likeBtn.textContent='❤️ Like';
    const counters = el('span','counters');
    const likes = el('span','likes-count'); likes.textContent = n.likes||0;
    const views = el('span','views-count'); views.textContent = n.views||0;
    const remain = el('span','remaining'); remain.textContent = typeof n.remaining==='number' ? fmtRemaining(n.remaining) : '';

    counters.append('👍 ', likes, ' · 👁️ ', views, ' · ', remain);
    meta.append(likeBtn, counters);

    card.append(actions, text, meta);

    // Like
    likeBtn.onclick = async ()=>{
      try{
        const r = await fetch(`/api/notes/${n.id}/like`, {method:'POST'});
        const j = await r.json().catch(()=>null);
        if (j && typeof j.likes==='number') likes.textContent = j.likes;
      }catch{}
    };

    // Report
    reportBtn.onclick = async ()=>{
      try{
        const r = await fetch(`/api/notes/${n.id}/report`, {method:'POST'});
        const j = await r.json().catch(()=>null);
        if (j && j.deleted){
          card.remove();
        } else if (j && typeof j.reports==='number'){
          reportBtn.textContent = `🚩 Reportar (${j.reports}/5)`;
        }
      }catch{}
      menuToggle(false);
    };

    // Share
    shareBtn.onclick = async ()=>{
      const url = location.origin + '/#n=' + n.id;
      try{
        if (navigator.share) await navigator.share({title:'Paste12', text:n.text, url});
        else {
          await navigator.clipboard.writeText(url);
          toast('Enlace copiado');
        }
      }catch{}
      menuToggle(false);
    };

    // Menú
    function menuToggle(force){
      const open = (force===undefined) ? menu.hidden : !force;
      menu.hidden = !open;
      menuBtn.setAttribute('aria-expanded', String(!menu.hidden));
    }
    menuBtn.onclick = (e)=>{ e.stopPropagation(); menuToggle(); };
    document.addEventListener('click', (e)=>{
      if (!card.contains(e.target)) menuToggle(false);
    });

    // View (enviar una vez por sesión al entrar en viewport)
    observeView(card, n.id, (count)=>{
      views.textContent = count;
    });

    return card;
  }

  // ===== Views observer =====
  function observeView(card, id, onCount){
    if (state.viewed.has(id)) return; // ya enviada en esta sesión
    ensureIOView();
    state.ioView.observe(card);
    card.__onView = async ()=>{
      if (state.viewed.has(id)) return;
      try{
        const r = await fetch(`/api/notes/${id}/view`, {method:'POST'});
        const j = await r.json().catch(()=>null);
        if (j && typeof j.views==='number') onCount(j.views);
      }catch{}
      state.viewed.add(id);
    };
  }
  function ensureIOView(){
    if (state.ioView) return;
    state.ioView = new IntersectionObserver((entries)=>{
      for (const e of entries){
        if (!e.isIntersecting) continue;
        const card = e.target;
        state.ioView.unobserve(card);
        card.__onView && card.__onView();
      }
    }, {root: null, threshold: 0.3, rootMargin: '100px 0px 200px 0px'});
  }

  // ===== Feed load + paging =====
  async function load(page=1){
    if (state.loading) return;
    state.loading = true;
    try{
      const r = await fetch(`/api/notes?page=${page}`, {headers:{'Accept':'application/json'}});
      const d = await r.json();
      const list = ensureList();
      const sentinel = ensureSentinel(list);

      // page 1 => limpio todo
      if (page===1){
        list.innerHTML = '';
        list.appendChild(sentinel);
        state.rendered.clear();
        // mantener viewed de sesión para no volver a contar vistas si refrescan
      }

      const notes = d.notes || [];
      for (let i=0;i<notes.length;i++){
        const n = notes[i];
        if (state.rendered.has(n.id)) continue;
        state.rendered.add(n.id);
        const card = cardFor(n);
        list.insertBefore(card, sentinel);
        // In-feed ad cada 6
        if ((i+1)%6===0) injectAd(list, sentinel);
      }

      state.page = d.page || page;
      state.hasMore = !!d.has_more;

      // (Re)activar IO solo si hay más
      ensureIOFeed();
      if (state.hasMore) {
        state.ioFeed.observe(sentinel);
      } else {
        try{ state.ioFeed.unobserve(sentinel); }catch{}
      }

    }catch(e){
      console.error('load failed', e);
    }finally{
      state.loading = false;
    }
  }

  function ensureIOFeed(){
    if (state.ioFeed) {
      try{ state.ioFeed.disconnect(); }catch{}
      state.ioFeed = null;
    }
    state.ioFeed = new IntersectionObserver((entries)=>{
      for (const e of entries){
        if (!e.isIntersecting) continue;
        if (state.loading || !state.hasMore) return;
        const next = (state.page||1) + 1;
        state.ioFeed.unobserve(e.target);
        load(next).then(()=>{
          // volver a observar si aún hay más
          if (state.hasMore) state.ioFeed.observe(e.target);
        });
      }
    }, {root:null, threshold:0, rootMargin:'200px 0px 600px 0px'});
  }

  // ===== Ads =====
  function injectAd(list, sentinel){
    const wrap = el('div','ad-slot infeed');
    wrap.innerHTML = `
      <ins class="adsbygoogle" style="display:block"
           data-ad-client=""
           data-ad-slot=""
           data-ad-format="fluid"
           data-ad-layout-key="-fg+5n+6t-1j-5u"
           data-full-width-responsive="true"></ins>`;
    list.insertBefore(wrap, sentinel);
    if (window.adsbygoogle) { try{ (adsbygoogle=window.adsbygoogle||[]).push({}); }catch{} }
  }

  // ===== utils =====
  function fmtRemaining(sec){
    sec = Math.max(0, parseInt(sec||0,10));
    const d = Math.floor(sec/86400); sec%=86400;
    const h = Math.floor(sec/3600); sec%=3600;
    const m = Math.floor(sec/60);
    if (d>0) return `${d}d ${h}h`;
    if (h>0) return `${h}h ${m}m`;
    return `${m}m`;
  }
  function toast(msg){
    let t = $('#__toast'); if (!t){ t=el('div','toast'); t.id='__toast'; document.body.appendChild(t); }
    t.textContent = msg; t.style.opacity='1';
    setTimeout(()=>{ t.style.opacity='0'; }, 1200);
  }

  // ===== Form publicar =====
  function bindForm(){
    const form = $('#new-note'); if (!form) return;
    const ta = $('textarea[name="text"]', form);
    const hint = $('#limit-hint');
    if (hint) hint.textContent = 'máx 10 por día';

    form.addEventListener('submit', async (ev)=>{
      ev.preventDefault();
      const text = (ta && ta.value || '').trim();
      if (!text) return;
      try{
        const r = await fetch('/api/notes', {
          method:'POST', headers:{'Content-Type':'application/json'},
          body: JSON.stringify({text, hours:12})
        });
        const j = await r.json().catch(()=>null);
        if (j && (j.id || (j.note && j.note.id))){
          ta.value = '';
          await load(1); // recargar feed (aparece arriba)
          window.scrollTo({top:0, behavior:'smooth'});
        } else if (j && j.error){
          toast(j.error);
        }
      }catch(e){ toast('Error publicando'); }
    }, {once:true});
  }

  document.addEventListener('DOMContentLoaded', ()=>{
    bindForm();
    load(1);
  });
})();
JS

# --- 3) Mensaje final ---
echo
echo "✅ Front listo (index + app.js)."
echo "   IMPORTANTE en Render → Environment:"
echo "   - ENABLE_VIEWS=1         (reactiva /view en backend si tenías kill-switch)"
echo "   - PAGE_SIZE=15           (o el que prefieras, 10..100)"
echo "   - MAX_NOTES=12000        (cap global)"
echo "   - PER_USER_DAILY=10      (si tu backend lo soporta; si no, lo añadimos luego)"
echo "   - ADSENSE_CLIENT=ca-pub-XXXXXXXXXXXXXXX  (si usás AdSense)"
echo
echo "Luego: git add frontend/index.html frontend/js/app.js && git commit -m 'front: reactivar todo (views+likes+report+share+ads)'; git push -u origin main"
echo "Y forza recarga: https://paste12-rmsk.onrender.com/?v=$(date +%s)"
