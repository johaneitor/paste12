(function(){
  if (window.P12Shared) return; // idempotent

  async function copyToClipboard(text){
    try{
      await navigator.clipboard.writeText(text);
      return true;
    }catch(_){
      const ta = document.createElement('textarea');
      ta.value = text; ta.style.position='fixed'; ta.style.top='-1000px';
      document.body.appendChild(ta); ta.select();
      const ok = document.execCommand('copy'); document.body.removeChild(ta);
      return ok;
    }
  }

  function noteUrl(id){
    return `${location.origin}/#n-${id}`;
  }

  function ensureToastEl(){
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
    return t;
  }

  function toast(msg){
    const t = ensureToastEl();
    t.textContent = msg;
    t.style.opacity='1'; t.style.transform='translateX(-50%) translateY(0)';
    setTimeout(()=>{ t.style.opacity='0'; t.style.transform='translateX(-50%) translateY(10px)'; }, 1500);
  }

  async function shareNoteId(id, opts){
    const url = noteUrl(id);
    const payload = Object.assign({title:'Paste12', text:'Mira esta nota', url}, opts||{});
    if (navigator.share && (!navigator.canShare || navigator.canShare({url}))){
      try { await navigator.share(payload); return true; }
      catch(_){ /* fallback a copiar */ }
    }
    const ok = await copyToClipboard(url);
    toast(ok ? 'Enlace copiado' : `Copia manual: ${url}`);
    return ok;
  }

  window.P12Shared = { noteUrl, copyToClipboard, toast, shareNoteId };
})();
