(function(){
  const state = {
    page: 1,
    hasMore: true,
    loading: false,
    rendered: new Set(),
    token: localStorage.getItem('p12t') || ''
  };

  const list = document.getElementById('feed') ||
               document.querySelector('main') ||
               document.body;

  // Sentinel para infinite scroll
  let sentinel = document.getElementById('sentinel');
  if (!sentinel) {
    sentinel = document.createElement('div');
    sentinel.id = 'sentinel';
    sentinel.style.height = '1px';
    list.appendChild(sentinel);
  }

  function fmtRemaining(sec){
    sec = Math.max(0, parseInt(sec||0,10));
    const d = Math.floor(sec/86400); sec%=86400;
    const h = Math.floor(sec/3600);  sec%=3600;
    const m = Math.floor(sec/60);
    if(d>0) return `${d}d ${h}h`;
    if(h>0) return `${h}h ${m}m`;
    return `${m}m`;
  }

  function cardFor(n){
    const card = document.createElement('div');
    card.className = 'note-card';
    card.dataset.id = n.id;

    card.innerHTML = `
      <div class="note-text"></div>
      <div class="note-meta">
        <button type="button" class="like-btn">❤️ Like</button>
        <span class="counters">
          👍 <span class="likes-count">${n.likes||0}</span> ·
          👁️ <span class="views-count">${n.views||0}</span>
        </span>
        <span class="remaining"></span>
        <button class="menu-btn" aria-haspopup="true" aria-expanded="false" title="Opciones">⋮</button>
        <div class="menu" hidden>
          <button type="button" class="menu-item report">🚩 Reportar</button>
          <button type="button" class="menu-item share">🔗 Compartir</button>
        </div>
      </div>
    `;

    card.querySelector('.note-text').textContent = n.text || '';
    if (n.remaining != null) {
      card.querySelector('.remaining').textContent = fmtRemaining(n.remaining);
    }

    // Like
    card.querySelector('.like-btn').addEventListener('click', async ()=>{
      try {
        const r = await fetch(`/api/notes/${n.id}/like`, { method:'POST', headers: { 'X-Client-Token': state.token }});
        const j = await r.json().catch(()=>({}));
        const el = card.querySelector('.likes-count');
        if (j && typeof j.likes === 'number' && el) el.textContent = j.likes;
      } catch(_) {}
    });

    // Menu simple (abrir/cerrar)
    const btn = card.querySelector('.menu-btn');
    const menu = card.querySelector('.menu');
    btn.addEventListener('click', ()=>{
      const vis = !menu.hidden;
      menu.hidden = vis;
      btn.setAttribute('aria-expanded', String(!vis));
    });

    // Report
    menu.querySelector('.report').addEventListener('click', async ()=>{
      try {
        const r = await fetch(`/api/notes/${n.id}/report`, { method:'POST', headers: { 'X-Client-Token': state.token }});
        const j = await r.json().catch(()=>({}));
        // Si se borró por 5 reportes, quitar del DOM:
        if (j && j.deleted) {
          state.rendered.delete(n.id);
          card.remove();
        }
      } catch(_) {}
    });

    // Share
    menu.querySelector('.share').addEventListener('click', async ()=>{
      const u = location.origin + '/?n=' + n.id;
      try {
        if (navigator.share) await navigator.share({title:'Nota', text:n.text||'', url:u});
        else await navigator.clipboard.writeText(u);
      } catch(_) {}
    });

    return card;
  }

  function render(notes){
    for (const n of notes) {
      if (state.rendered.has(n.id)) continue; // DEDUPE
      state.rendered.add(n.id);

      const card = cardFor(n);
      list.insertBefore(card, sentinel);

      // Conteo de vista SOLO 1 vez por sesión por nota
      const key = 'v_' + n.id;
      if (!sessionStorage.getItem(key)) {
        sessionStorage.setItem(key, '1');
        fetch(`/api/notes/${n.id}/view`, { method:'POST' }).then(r=>r.json()).then(j=>{
          const el = card.querySelector('.views-count');
          if (el && j && typeof j.views === 'number') el.textContent = j.views;
        }).catch(()=>{});
      }
    }
  }

  async function load(page){
    if (state.loading) return;
    state.loading = true;
    try {
      const r = await fetch(`/api/notes?page=${page}`);
      const d = await r.json();

      if (page === 1) {
        // Limpiar DOM y el set para evitar duplicados al recargar
        [...list.querySelectorAll('.note-card')].forEach(x=>x.remove());
        state.rendered.clear();
      }

      render(d.notes || []);
      state.page = page;
      state.hasMore = !!d.has_more;
    } catch (e) {
      console.error('load fail', e);
    } finally {
      state.loading = false;
    }
  }

  const io = new IntersectionObserver((entries)=>{
    if (!state.hasMore || state.loading) return;
    for (const e of entries) {
      if (e.isIntersecting) {
        io.unobserve(sentinel);
        load(state.page + 1).finally(()=>{
          if (state.hasMore) io.observe(sentinel);
        });
      }
    }
  }, { rootMargin: '800px' });

  document.addEventListener('DOMContentLoaded', ()=>{
    load(1).then(()=>{
      if (state.hasMore) io.observe(sentinel);
    });
  });
})();
