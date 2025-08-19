(function(){
  function noteUrl(id){ return `${location.origin}/#n-${id}`; }

  async function copyToClipboard(text){
    try{
      await navigator.clipboard.writeText(text);
      return true;
    }catch(_){
      // Fallback execCommand
      const ta = document.createElement('textarea');
      ta.value = text;
      ta.style.position = 'fixed';
      ta.style.top = '-1000px';
      document.body.appendChild(ta);
      ta.select();
      const ok = document.execCommand('copy');
      document.body.removeChild(ta);
      return ok;
    }
  }

  function toast(msg){
    let t = document.getElementById('toast-share');
    if(!t){
      t = document.createElement('div');
      t.id = 'toast-share';
      Object.assign(t.style, {
        position:'fixed', left:'50%', bottom:'16px', transform:'translateX(-50%) translateY(10px)',
        background:'#111a', color:'#fff', padding:'10px 14px', borderRadius:'10px',
        backdropFilter:'blur(6px)', zIndex:'9999', fontSize:'14px', opacity:'0',
        transition:'opacity .2s, transform .2s'
      });
      document.body.appendChild(t);
    }
    t.textContent = msg;
    t.style.opacity = '1';
    t.style.transform = 'translateX(-50%) translateY(0)';
    setTimeout(()=>{ t.style.opacity='0'; t.style.transform='translateX(-50%) translateY(10px)'; }, 1500);
  }

  async function doShare(id){
    const url = noteUrl(id);
    if (navigator.share && (!navigator.canShare || navigator.canShare({url}))){
      try { await navigator.share({title:'Paste12', text:'Mira esta nota', url}); return; }
      catch(e){ /* cancelado por el usuario → fallback a copiar */ }
    }
    const ok = await copyToClipboard(url);
    toast(ok ? 'Enlace copiado' : `Copia manual: ${url}`);
  }

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
      if (id) doShare(id);
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
