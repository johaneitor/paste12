(function(){
  const $status = document.getElementById('status') || (()=>{const s=document.createElement('span');s.id='status';document.body.appendChild(s);return s;})();
  const $list = document.getElementById('notes') || (()=>{const u=document.createElement('ul');u.id='notes';document.body.appendChild(u);return u;})();
  const $form = document.getElementById('noteForm');

  function fmtISO(s){ try{ return new Date(s).toLocaleString(); }catch(_){ return s||''; } }

  function toast(msg){
    let t = document.getElementById('toast');
    if(!t){
      t = document.createElement('div');
      t.id='toast';
      t.style.cssText='position:fixed;left:50%;bottom:18px;transform:translateX(-50%);background:#111a;color:#eaf2ff;padding:10px 14px;border-radius:10px;border:1px solid #253044;z-index:9999;transition:opacity .25s ease';
      document.body.appendChild(t);
    }
    t.textContent = msg;
    t.style.opacity='1';
    setTimeout(()=>{ t.style.opacity='0'; }, 1800);
  }

  function noteLink(id){
    try{ return location.origin + '/?note=' + id; }catch(_){ return '/?note='+id; }
  }

  async function reportNote(id){
    try{
      const res = await fetch('/api/notes/'+id+'/report', { method: 'POST' });
      const data = await res.json();
      if(data.deleted){
        const el = document.getElementById('note-'+id);
        if(el) el.remove();
        toast('Nota eliminada por reportes (5/5)');
      }else if(data.already_reported){
        toast('Ya reportaste esta nota');
      }else if(data.ok){
        toast('Reporte registrado ('+(data.reports||0)+'/5)');
      }else{
        alert('No se pudo reportar: '+(data.detail||''));
      }
    }catch(e){ alert('Error de red al reportar'); }
  }

  async function shareNote(id){
    const url = noteLink(id);
    if(navigator.share){
      try{ await navigator.share({ title: 'Nota #'+id, url }); return; }catch(_){}
    }
    try{ await navigator.clipboard.writeText(url); toast('Enlace copiado'); }
    catch(_){ window.prompt('Copia este enlace', url); }
  }

  function renderNote(n){
    const li = document.createElement('li');
    li.className = 'note';
    li.id = 'note-'+n.id;

    // fila principal
    const row = document.createElement('div');
    row.className = 'row';

    const txt = document.createElement('div');
    txt.className = 'txt';
    txt.textContent = String(n.text ?? '');

    const more = document.createElement('button');
    more.className = 'more';
    more.setAttribute('aria-label','Más opciones');
    more.textContent = '⋯';

    const menu = document.createElement('div');
    menu.className = 'menu';

    // items de menú
    const btnReport = document.createElement('button');
    btnReport.textContent = 'Reportar';
    btnReport.addEventListener('click', (ev)=>{ ev.stopPropagation(); menu.classList.remove('open'); reportNote(n.id); });

    const btnShare = document.createElement('button');
    btnShare.textContent = 'Compartir';
    btnShare.addEventListener('click', (ev)=>{ ev.stopPropagation(); menu.classList.remove('open'); shareNote(n.id); });

    menu.appendChild(btnReport);
    menu.appendChild(btnShare);

    more.addEventListener('click', (ev)=>{
      ev.stopPropagation();
      menu.classList.toggle('open');
    });

    row.appendChild(txt);
    row.appendChild(more);
    row.appendChild(menu);

    const meta = document.createElement('div');
    meta.className = 'meta';
    meta.appendChild(document.createTextNode('id #'+n.id+' · '+fmtISO(n.timestamp)+' · expira: '+fmtISO(n.expires_at)));

    li.appendChild(row);
    li.appendChild(meta);
    return li;
  }

  async function fetchNotes(){
    $status.textContent = 'cargando…';
    try{
      const res = await fetch('/api/notes?page=1');
      const data = await res.json();
      $list.innerHTML = '';
      data.forEach(n => $list.appendChild(renderNote(n)));
      $status.textContent = 'ok';
    }catch(e){
      console.error(e);
      $status.textContent = 'error cargando';
    }
  }

  // click fuera cierra menús
  document.addEventListener('click', ()=> {
    document.querySelectorAll('.note .menu.open').forEach(el => el.classList.remove('open'));
  });

  if($form){
    $form.addEventListener('submit', async (ev)=>{
      ev.preventDefault();
      const fd = new FormData($form);
      try{
        const res = await fetch('/api/notes', { method:'POST', body: fd });
        if(!res.ok) throw new Error('HTTP '+res.status);
        await fetchNotes();
        $form.reset();
        const h = document.getElementById('hours'); if(h) h.value = 24;
      }catch(e){
        alert('No se pudo publicar la nota: '+e.message);
      }
    });
  }

  // scroll a ?note=ID si viene en la URL
  try{
    const params = new URLSearchParams(location.search);
    const id = params.get('note');
    if(id){
      setTimeout(()=>{
        const el = document.getElementById('note-'+id);
        if(el) el.scrollIntoView({behavior:'smooth', block:'center'});
      }, 150);
    }
  }catch(_){}

  fetchNotes();
})();
