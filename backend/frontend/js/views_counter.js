(function(){
  const SEEN_KEY = (id)=>`p12:viewed:${id}`;
  const NOTES_SEL = '#notes, [data-notes], #list, main, body';

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
      (j.items||[]).forEach(n => cache.set(String(n.id), n));
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
      m.innerHTML = `<span class="p12-views" title="Vistas">👁 0</span>`;
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
      if (sessionStorage.getItem(SEEN_KEY(id))) return; // ya sumado en esta sesión
      const res = await fetch(`/api/notes/${id}/view`, {method:'POST'});
      const j = await res.json();
      setViews(card, j.views ?? '?');
      sessionStorage.setItem(SEEN_KEY(id), '1');
    }catch(e){
      console.warn('[views] fallo al sumar', e);
    }
  }

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
      // suma 1 vez por sesión en primera visualización
      addViewOnce(id, card);
    });
  }

  document.addEventListener('DOMContentLoaded', ()=>{
    const container = document.querySelector(NOTES_SEL);
    if(!container) return;
    process(container);

    // Observa cambios (paginación, nuevas notas)
    const mo = new MutationObserver(()=>{
      process(container);
    });
    mo.observe(container, {childList:true, subtree:true});
    console.log('[views_counter] activo');
  });
})();
