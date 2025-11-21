(function(){
  // ===== Utils =====
  function noteUrl(id){ return `${location.origin}/#n-${id}`; }

  async function copyToClipboard(text){
    try{ await navigator.clipboard.writeText(text); return true; }
    catch(_){
      const ta = document.createElement('textarea');
      ta.value = text; ta.style.position='fixed'; ta.style.top='-1000px';
      document.body.appendChild(ta); ta.select();
      const ok = document.execCommand('copy'); document.body.removeChild(ta);
      return ok;
    }
  }

  function toast(msg){
    let t = document.getElementById('toast-p12');
    if(!t){
      t = document.createElement('div'); t.id='toast-p12';
      Object.assign(t.style, {
        position:'fixed', left:'50%', bottom:'16px', transform:'translateX(-50%) translateY(10px)',
        background:'#111a', color:'#fff', padding:'10px 14px', borderRadius:'10px',
        backdropFilter:'blur(6px)', zIndex:'9999', fontSize:'14px', opacity:'0',
        transition:'opacity .2s, transform .2s'
      });
      document.body.appendChild(t);
    }
    t.textContent = msg;
    t.style.opacity='1'; t.style.transform='translateX(-50%) translateY(0)';
    setTimeout(()=>{ t.style.opacity='0'; t.style.transform='translateX(-50%) translateY(10px)'; }, 1500);
  }

  async function shareNote(id){
    const url = noteUrl(id);
    if (navigator.share && (!navigator.canShare || navigator.canShare({url}))){
      try { await navigator.share({title:'Paste12', text:'Mira esta nota', url}); return; }
      catch(e){/* cancelado → fallback a copiar */}
    }
    const ok = await copyToClipboard(url);
    toast(ok ? 'Enlace copiado' : `Copia manual: ${url}`);
  }

  async function reportNote(id, card){
    try{
      const res = await fetch(`/api/notes/${id}/report`, {method:'POST', headers:{'Content-Type':'application/json'}});
      const j = await res.json();
      if (j.deleted){
        // Borrar del DOM
        card?.remove();
        toast('La nota fue eliminada por reportes');
      } else if (j.already_reported){
        toast('Ya reportaste esta nota');
      } else {
        toast(`Reporte enviado (${j.reports}/5)`);
      }
    }catch(e){
      console.warn('report failed', e);
      toast('No se pudo reportar');
    }
  }

  // ===== DOM helpers =====
  function getIdFromCard(card){
    return card.getAttribute('data-note')
      || card.getAttribute('data-note-id')
      || (card.dataset ? (card.dataset.note || card.dataset.id) : null)
      || null;
  }

  function ensureAnchorId(card, id){
    if (!card.id) card.id = 'n-'+id;
  }

  function ensureMenu(card, id){
    if (card.querySelector('.p12-menu-wrap')) return;

    // contenedor absoluto arriba-dcha
    const wrap = document.createElement('div');
    wrap.className = 'p12-menu-wrap';
    const btn = document.createElement('button');
    btn.type = 'button'; btn.className = 'p12-menu-btn'; btn.setAttribute('aria-label','Opciones'); btn.textContent = '⋯';
    const panel = document.createElement('div'); panel.className = 'p12-menu'; panel.setAttribute('hidden','');
    const share = document.createElement('button'); share.type='button'; share.className='p12-share'; share.textContent='Compartir';
    const report = document.createElement('button'); report.type='button'; report.className='p12-report'; report.textContent='Reportar';
    panel.appendChild(share); panel.appendChild(report); wrap.appendChild(btn); wrap.appendChild(panel);
    card.style.position = card.style.position || 'relative';
    card.appendChild(wrap);

    const menu = panel;

    share.dataset.noteId = id;
    report.dataset.noteId = id;
  }

  function process(container){
    container.querySelectorAll('[data-note], [data-note-id], .note-card, article, li').forEach(card=>{
      const id = getIdFromCard(card);
      if (!id) return;
      ensureAnchorId(card, id);
      ensureMenu(card, id);
    });
  }

  function closeAllMenus(except){
    document.querySelectorAll('.p12-menu').forEach(menu=>{
      if (menu !== except) menu.setAttribute('hidden','');
    });
  }

  function handleGlobalClick(event){
    const btn = event.target.closest('.p12-menu-btn');
    if (btn){
      const wrap = btn.closest('.p12-menu-wrap');
      const menu = wrap?.querySelector('.p12-menu');
      if (!menu) return;
      const willOpen = menu.hasAttribute('hidden');
      closeAllMenus(menu);
      if (willOpen) menu.removeAttribute('hidden'); else menu.setAttribute('hidden','');
      event.stopPropagation();
      return;
    }

    const share = event.target.closest('.p12-share');
    if (share){
      const card = share.closest('[data-note], [data-note-id], .note-card, article, li');
      const id = share.dataset.noteId || getIdFromCard(card);
      closeAllMenus();
      if (id) shareNote(id);
      event.stopPropagation();
      return;
    }

    const report = event.target.closest('.p12-report');
    if (report){
      const card = report.closest('[data-note], [data-note-id], .note-card, article, li');
      const id = report.dataset.noteId || getIdFromCard(card);
      closeAllMenus();
      if (id) reportNote(id, card);
      event.stopPropagation();
      return;
    }

    if (!event.target.closest('.p12-menu')){
      closeAllMenus();
    }
  }

  document.addEventListener('DOMContentLoaded', ()=>{
    const container = document.getElementById('notes')
      || document.querySelector('[data-notes]')
      || document.querySelector('#list')
      || document.querySelector('main')
      || document.body;

    process(container);
    const mo = new MutationObserver(()=>process(container));
    mo.observe(container, {childList:true, subtree:true});
    console.log('[actions_menu] listo (⋯ → Compartir/Reportar sin popups)');
    document.addEventListener('click', handleGlobalClick);
  });
})();
