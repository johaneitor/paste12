(function(){
  const SEEN_KEY = (id)=>`p12:viewed:${id}`;
  const ATTEMPT_KEY = (id)=>`p12:viewAttempted:${id}`;
  const NOTES_SEL = '#notes, [data-notes], #list, main, body';

  // Global guard to avoid duplicate view POSTs across modules
  const globalGuard = (function(){
    if (!window.__p12ViewOnceGuard) window.__p12ViewOnceGuard = new Set();
    return window.__p12ViewOnceGuard;
  })();

  // map de id -> {views,...} del listado actual
  const cache = new Map();
  let fetching = false;

  function getCurrentPage(){
    const u = new URL(location.href);
    const p = parseInt(u.searchParams.get('page')||'1',10);
    return isNaN(p)||p<1 ? 1 : p;
  }

  async function hydrateCache(){
    if (fetching) return;
    fetching = true;
    try{
      const page = getCurrentPage();
      const r = await fetch(`/api/notes?page=${page}`);
      const j = await r.json();
      const arr = Array.isArray(j) ? j : (Array.isArray(j.items) ? j.items : (Array.isArray(j.notes) ? j.notes : []));
      arr.forEach(n => cache.set(String(n.id), n));
    }catch(e){ console.warn('[views] no se pudo hidratar', e); }
    finally{ fetching = false; }
  }

  function getIdFromCard(card){
    return card.getAttribute('data-note')
      || card.getAttribute('data-note-id')
      || (card.dataset ? (card.dataset.note || card.dataset.id) : null)
      || (card.id && card.id.startsWith('n-') ? card.id.slice(2) : null)
      || null;
  }

  function ensureMetrics(card){
    let m = card.querySelector('.p12-metrics');
    if (!m){
      m = document.createElement('div');
      m.className = 'p12-metrics';
      const span = document.createElement('span');
      span.className = 'p12-views';
      span.title = 'Vistas';
      span.textContent = '👁 0';
      m.appendChild(span);
      card.appendChild(m);
    }
    return m;
  }

  function setViews(card, count){
    const span = card.querySelector('.p12-views');
    if (span) span.textContent = `👁 ${count}`;
  }

  async function addViewOnce(id, card){
    try{
      if (!id) return;
      if (globalGuard.has(id)) return;
      if (sessionStorage.getItem(SEEN_KEY(id))) { globalGuard.add(id); return; }
      if (sessionStorage.getItem(ATTEMPT_KEY(id))) return; // evitar tormenta en fallos
      // Marca el intento antes del fetch para no reintentar en bucles/errores
      sessionStorage.setItem(ATTEMPT_KEY(id), '1');
      globalGuard.add(id);
      // Defer al próximo idle para no competir con el render y evitar ráfagas
      await new Promise(res=> (window.requestIdleCallback? requestIdleCallback(res, {timeout: 1200}) : setTimeout(res, 0)) );
      const res = await fetch(`/api/notes/${id}/view`, {method:'POST'});
      const j = await res.json().catch(()=>({}));
      if (j && typeof j.views !== 'undefined') setViews(card, j.views ?? '?');
      // Marca como visto independientemente del conteo para evitar reintentos agresivos
      sessionStorage.setItem(SEEN_KEY(id), '1');
    }catch(e){
      console.warn('[views] fallo al sumar', e);
    }
  }

  const USE_IO = typeof IntersectionObserver !== 'undefined';

  async function process(container){
    // hidratar cache una sola vez por corrida
    if (cache.size === 0) await hydrateCache();

    container.querySelectorAll('[data-note], [data-note-id], .note-card, article, li').forEach(card=>{
      const id = getIdFromCard(card);
      if (!id) return;
      card.style.position = card.style.position || 'relative';
      ensureMetrics(card);
      // si sabemos la cifra desde cache del listado, muéstrala
      if (cache.has(String(id))) setViews(card, cache.get(String(id)).views ?? 0);
      // Si no hay IntersectionObserver disponible, hacemos fallback inmediato
      if (!USE_IO) addViewOnce(id, card);
    });
  }

  // Defer hasta 'load' para no competir con el render inicial y observar visibilidad
  window.addEventListener('load', ()=>{
    const container = document.querySelector(NOTES_SEL);
    if(!container) return;
    // Solo contar cuando los elementos son visibles en viewport (si IO existe)
    var io = null;
    if (USE_IO) {
      io = new IntersectionObserver(function(entries){
        entries.forEach(function(e){
          if (!e.isIntersecting) return;
          var card = e.target;
          var id = getIdFromCard(card);
          if (id) addViewOnce(id, card);
          io.unobserve(card);
        });
      }, {root: null, rootMargin: '0px', threshold: 0.4});
    }

    // Inicializar render/hidratación y observar tarjetas
    process(container);
    if (io) container.querySelectorAll('[data-note], [data-note-id], .note-card, article, li').forEach(el=> io.observe(el));

    // Observa cambios (paginación, nuevas notas)
    const mo = new MutationObserver(()=>{ process(container); if (io) container.querySelectorAll('[data-note], [data-note-id], .note-card, article, li').forEach(el=> io.observe(el)); });
    mo.observe(container, {childList:true, subtree:true});
    console.log('[views_counter] activo');
  });
})();
