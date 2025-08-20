(()=>{ if (window.__P12_STABLE) return; window.__P12_STABLE=true;

  // Evitar múltiples inicializaciones
  if (window.__P12_INIT_ONCE) return; window.__P12_INIT_ONCE = true;

  // Vistas: una por ID y por navegador (persistente)
  const viewed = new Set();
  try {
    JSON.parse(localStorage.getItem('p12_viewed')||'[]').forEach(id=>viewed.add(String(id)));
  } catch(e){}

  function persist(){
    try{ localStorage.setItem('p12_viewed', JSON.stringify([...viewed])); }catch(e){}
  }

  async function sendView(id){
    id = String(id);
    if (viewed.has(id)) return;
    viewed.add(id); persist();
    try{
      await fetch(`/api/notes/${id}/view`, {method:'POST', headers:{'Content-Type':'application/json'}, keepalive:true});
    }catch(e){}
  }

  let io;
  function ensureIO(){
    if (io) return io;
    io = new IntersectionObserver(entries=>{
      entries.forEach(en=>{
        if (en.isIntersecting && en.intersectionRatio >= 0.5){
          const card = en.target;
          const id = card.getAttribute('data-id') || card.dataset.id;
          if (!id) return;
          if (card.dataset.viewSent==='1') { io.unobserve(card); return; }
          card.dataset.viewSent='1';
          sendView(id);
          io.unobserve(card);
        }
      });
    }, {threshold:[0.5]});
    return io;
  }

  function observeCards(){
    const o = ensureIO();
    document.querySelectorAll('.note-card').forEach(card=>{
      if (card.dataset.observed==='1') return;
      card.dataset.observed='1';
      o.observe(card);
    });
  }

  // Observar cambios del DOM (cuando se renderizan notas)
  const mo = new MutationObserver(()=>observeCards());
  mo.observe(document.body, {childList:true, subtree:true});
  window.addEventListener('load', observeCards);

  // Guardas para evitar duplicar listeners globales de compartir/acciones
  if (!window.__P12_GLOBAL_EVENTS){
    window.__P12_GLOBAL_EVENTS = true;
    // (si tus scripts ya manejan compartir, no hacemos nada aquí)
  }
})();
