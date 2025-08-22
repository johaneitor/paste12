
function noteLink(id){
  try { return location.origin + "/?note=" + id; } catch { return "/?note="+id; }
}
async function reportNote(id){
  try{
    const res = await fetch(`/api/notes/${id}/report`, {method: 'POST'});
    const data = await res.json();
    if (data.deleted){
      const el = document.getElementById(`note-${id}`);
      if (el) el.remove();
      toast('Nota eliminada por reportes (5/5)');
    }else if (data.already_reported){
      toast('Ya reportaste esta nota');
    }else if (data.ok){
      toast(`Reporte registrado (${data.reports}/5)`);
    }else{
      alert('No se pudo reportar: ' + (data.detail||''));
    }
  }catch(e){ alert('Error de red al reportar'); }
}
async function shareNote(id){
  const url = noteLink(id);
  if (navigator.share){
    try{ await navigator.share({title:'Nota #' + id, url}); return; }catch(e){}
  }
  try{
    await navigator.clipboard.writeText(url);
    toast('Enlace copiado');
  }catch(e){
    prompt('Copia este enlace:', url);
  }
}
function toast(msg){
  let t = document.getElementById('toast');
  if (!t){
    t = document.createElement('div');
    t.id='toast';
    t.style.cssText='position:fixed;left:50%;bottom:18px;transform:translateX(-50%);background:#111a;color:#eaf2ff;padding:10px 14px;border-radius:10px;border:1px solid #253044;z-index:9999';
    document.body.appendChild(t);
  }
  t.textContent = msg;
  t.style.opacity='1';
  setTimeout(()=>{ t.style.opacity='0'; }, 1800);
}

(function () {
  const $status = document.getElementById('status');
  const $list = document.getElementById('notes');
  const $form = document.getElementById('noteForm');

  function fmtISO(s) {
    try { return new Date(s).toLocaleString(); } catch { return s; }
  }

  async function fetchNotes() {
    $status.textContent = 'cargando…';
    try {
      const res = await fetch('/api/notes?page=1');
      const data = await res.json();
      $list.innerHTML = '';
      data.forEach(n => {
        const li = document.createElement('li');
li.className='note';
li.id = `note-${n.id}`;
        li.innerHTML = `
      <div class="row">
        <div class="txt">\${n.text ?? ''}</div>
        <button class="more" aria-label="Más opciones" onclick="this.nextElementSibling.classList.toggle('open')">⋯</button>
        <div class="menu">
          <button onclick="reportNote(\${n.id})">Reportar</button>
          <button onclick="shareNote(\${n.id})">Compartir</button>
        </div>
      </div>
      <div class="meta">
        <span>id #\${n.id}</span>
        <span> · </span>
        <span>\${fmtISO(n.timestamp)}</span>
        <span> · expira: \${fmtISO(n.expires_at)}</span>
      </div>`;
        $list.appendChild(li);
      });
      $status.textContent = 'ok';
    } catch (e) {
      console.error(e);
      $status.textContent = 'error cargando';
    }
  }

  $form.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const fd = new FormData($form);
    try {
      const res = await fetch('/api/notes', { method: 'POST', body: fd });
      if (!res.ok) throw new Error('HTTP ' + res.status);
      // refrescar
      await fetchNotes();
      $form.reset();
      document.getElementById('hours').value = 24;
    } catch (e) {
      alert('No se pudo publicar la nota: ' + e.message);
    }
  });

  fetchNotes();
})();

(function(){
  try{
    const params = new URLSearchParams(location.search);
    const h = params.get('note');
    if (h){
      const el = document.getElementById('note-' + h);
      if (el) el.scrollIntoView({behavior:'smooth', block:'center'});
    }
  }catch(e){}
})();
