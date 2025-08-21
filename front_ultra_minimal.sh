#!/usr/bin/env bash
set -Eeuo pipefail
js="frontend/js/app.js"
bak="frontend/js/app.js.bak.$(date +%s)"
cp -f "$js" "$bak" 2>/dev/null || true

cat > "$js" <<'JS'
// Ultra-minimal feed (dedupe + infinite scroll gated by has_more)
// Sin dependencias, robusto ante recargas, evita duplicados por ID.

(function(){
  const state = {
    page: 1,
    pageSize: 15,
    hasMore: true,
    loading: false,
    rendered: new Set(),
    io: null
  };

  function el(tag, cls){ const e=document.createElement(tag); if(cls) e.className=cls; return e; }

  function ensureList(){
    let list = document.getElementById('feed');
    if (!list) {
      list = el('div','feed');
      list.id = 'feed';
      document.body.appendChild(list);
    }
    return list;
  }

  function ensureSentinel(list){
    let s = document.getElementById('sentinel');
    if (!s) {
      s = el('div'); s.id='sentinel'; s.style.height='1px';
      list.appendChild(s);
    } else if (!s.parentNode) {
      list.appendChild(s);
    }
    return s;
  }

  function cardFor(n){
    const card = el('div','note-card');
    card.dataset.id = n.id;
    const text = el('div','note-text'); text.textContent = n.text || '';
    const meta = el('div','note-meta');
    const likes = el('span','likes-count'); likes.textContent = (n.likes||0);
    const views = el('span','views-count'); views.textContent = (n.views||0);
    const remain = el('span','remaining'); if (typeof n.remaining === 'number') remain.textContent = fmtRemaining(n.remaining);

    const likeBtn = el('button','like-btn'); likeBtn.textContent = '❤️ Like';
    likeBtn.onclick = async ()=>{
      try{
        const r = await fetch(`/api/notes/${n.id}/like`, {method:'POST'});
        const j = await r.json();
        likes.textContent = (j && typeof j.likes === 'number') ? j.likes : likes.textContent;
      }catch{}
    };

    const actionBar = el('div','counters');
    actionBar.append(`👍 `, likes, ` · 👁️ `, views, ' · ', remain);

    meta.appendChild(likeBtn);
    meta.appendChild(actionBar);

    card.appendChild(text);
    card.appendChild(meta);
    return card;
  }

  function fmtRemaining(sec){
    sec = Math.max(0, parseInt(sec||0,10));
    const d = Math.floor(sec/86400); sec%=86400;
    const h = Math.floor(sec/3600); sec%=3600;
    const m = Math.floor(sec/60);
    if(d>0) return `${d}d ${h}h`;
    if(h>0) return `${h}h ${m}m`;
    return `${m}m`;
  }

  async function load(page=1){
    if (state.loading) return;
    state.loading = true;
    try{
      const r = await fetch(`/api/notes?page=${page}`, {headers:{'Accept':'application/json'}});
      const d = await r.json();
      const list = ensureList();
      const sentinel = ensureSentinel(list);

      // page 1 => limpiar DOM y set de IDs
      if (page === 1){
        list.innerHTML = '';
        list.appendChild(sentinel);
        state.rendered.clear();
      }

      const notes = d.notes || [];
      for (const n of notes){
        if (state.rendered.has(n.id)) continue; // DEDUPE
        state.rendered.add(n.id);
        const card = cardFor(n);
        list.insertBefore(card, sentinel);
      }

      state.page = d.page || page;
      state.hasMore = !!d.has_more;

      // (Re)activar IO sólo si hay más páginas
      if (state.io) {
        try { state.io.disconnect(); } catch {}
        state.io = null;
      }
      if (state.hasMore){
        state.io = new IntersectionObserver((entries)=>{
          for (const e of entries){
            if (!e.isIntersecting) continue;
            if (state.loading || !state.hasMore) return;
            // cargar siguiente página UNA sola vez por intersección
            const next = (state.page || 1) + 1;
            state.io && state.io.unobserve(e.target);
            load(next).then(()=>{
              if (state.hasMore) state.io && state.io.observe(e.target);
            });
          }
        }, {rootMargin: '200px 0px 200px 0px'});
        state.io.observe(sentinel);
      }
    }catch(e){
      console.error('load failed', e);
    }finally{
      state.loading = false;
    }
  }

  // Soporte envío de notas si hay <form>
  function bindForm(){
    const form = document.querySelector('form');
    if (!form) return;
    const ta = form.querySelector('textarea[name="text"], textarea, [data-note-text]');

    form.addEventListener('submit', async (ev)=>{
      ev.preventDefault();
      const text = (ta && ta.value || '').trim();
      if (!text) return;
      try{
        const r = await fetch('/api/notes', {
          method: 'POST',
          headers: {'Content-Type':'application/json'},
          body: JSON.stringify({text, hours:12})
        });
        const j = await r.json();
        // Prefetch page 1 de nuevo para ver la nueva nota arriba
        state.page = 1;
        await load(1);
        if (ta) ta.value = '';
      }catch(e){ console.error('submit failed', e); }
    }, {once:true});
  }

  document.addEventListener('DOMContentLoaded', ()=>{
    bindForm();
    load(1);
  });
})();
JS

echo "Backup: $bak"
echo "Nuevo:  $js"
