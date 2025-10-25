(function(){
  const { shareNoteId } = window.P12Shared || {};
  if (!shareNoteId) return;

  function findContainer(){
    return document.getElementById('notes')
        || document.querySelector('[data-notes]')
        || document.querySelector('#list')
        || document.querySelector('main')
        || document.body;
  }

  function getCardId(card){
    return card.getAttribute('data-note')
        || card.getAttribute('data-note-id')
        || (card.dataset ? (card.dataset.note || card.dataset.id) : null)
        || null;
  }

  function ensureAnchorId(card, id){
    if (!card.id) card.id = 'n-' + id;
  }

  function injectShareIfMissing(card, id){
    if(card.querySelector('[data-share-id], .btn-share, .menu-share, .share-link')) return;
    // Coloca el botón en la fila meta o crea una
    let meta = card.querySelector('.note-meta');
    if(!meta){
      meta = document.createElement('div');
      meta.className = 'note-meta';
      Object.assign(meta.style, {display:'flex', alignItems:'center', gap:'10px', marginTop:'8px'});
      card.appendChild(meta);
    }
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'btn-share';
    btn.setAttribute('data-share-id', id);
    btn.textContent = 'Compartir';
    Object.assign(btn.style, {border:'0', background:'#17325b', color:'#fff', padding:'6px 10px', borderRadius:'10px', cursor:'pointer'});
    meta.appendChild(btn);
  }

  function processExisting(container){
    container.querySelectorAll('[data-note], [data-note-id], .note-card, article').forEach(card=>{
      const id = getCardId(card);
      if(!id) return;
      ensureAnchorId(card, id);
      injectShareIfMissing(card, id);
    });
  }

  function interceptClicks(container){
    container.addEventListener('click', (ev)=>{
      // Captura clicks de compartir (y anula popups tipo Twitter antiguos)
      const target = ev.target.closest('[data-share-id], .btn-share, .menu-share, .share-link, .share-twitter, .share-x, a[href*="twitter.com/intent"]');
      if(!target) return;
      ev.preventDefault();
      const id = target.getAttribute('data-share-id')
        || target.getAttribute('data-note-id')
        || target.dataset?.note
        || target.dataset?.id
        || getCardId(target.closest('[data-note], [data-note-id], .note-card, article')) ;
      if (id) shareNoteId(id);
    });
  }

  document.addEventListener('DOMContentLoaded', ()=>{
    const container = findContainer();
    processExisting(container);
    interceptClicks(container);
    // Si llegan nuevas tarjetas por JS, asegúralo también
    const mo = new MutationObserver(()=>processExisting(container));
    mo.observe(container, {childList:true, subtree:true});
    console.log('[share_enhancer] activo (sin popups; share sheet en móvil; copia en escritorio)');
  });
})();
