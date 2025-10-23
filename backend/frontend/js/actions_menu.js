(function(){
  const { shareNoteId, toast } = window.P12Shared || {};
  if (!shareNoteId || !toast) return;

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
    wrap.innerHTML = `
      <button type="button" class="p12-menu-btn" aria-label="Opciones">⋯</button>
      <div class="p12-menu" hidden>
        <button type="button" class="p12-share">Compartir</button>
        <button type="button" class="p12-report">Reportar</button>
      </div>`;
    card.style.position = card.style.position || 'relative';
    card.appendChild(wrap);

    const btn = wrap.querySelector('.p12-menu-btn');
    const menu = wrap.querySelector('.p12-menu');
    const share = wrap.querySelector('.p12-share');
    const report = wrap.querySelector('.p12-report');

    btn.addEventListener('click', (e)=>{
      e.stopPropagation();
      const v = menu.hasAttribute('hidden');
      document.querySelectorAll('.p12-menu').forEach(m=>m.setAttribute('hidden',''));
      if (v) menu.removeAttribute('hidden'); else menu.setAttribute('hidden','');
    });

    share.addEventListener('click', (e)=>{ e.stopPropagation(); menu.setAttribute('hidden',''); shareNoteId(id); });
    report.addEventListener('click', (e)=>{ e.stopPropagation(); menu.setAttribute('hidden',''); reportNote(id, card); });

    // cerrar al clicar fuera
    document.addEventListener('click', ()=> menu.setAttribute('hidden',''));
  }

  function process(container){
    container.querySelectorAll('[data-note], [data-note-id], .note-card, article, li').forEach(card=>{
      const id = getIdFromCard(card);
      if (!id) return;
      ensureAnchorId(card, id);
      ensureMenu(card, id);
    });
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
  });
})();
