(function(){
  function loadAdsenseOnce(){
    try{
      const meta = document.querySelector('meta[name="ads-client"]');
      const client = meta && meta.content || '';
      if(!client || client.includes('XXXX')) return; // placeholder => no carga
      if(document.getElementById('adsbygoogle-lib')) return;
      const sc = document.createElement('script');
      sc.id='adsbygoogle-lib';
      sc.async = true;
      sc.src = "https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client="+encodeURIComponent(client);
      sc.crossOrigin = "anonymous";
      document.head.appendChild(sc);
      setTimeout(()=>{ try{ (window.adsbygoogle=window.adsbygoogle||[]).push({}); }catch(_){ } }, 1200);
    }catch(_){}
  }
  loadAdsenseOnce();
  // UID para unicidad de like/view
  (function ensureUid(){
    try{
      if(document.cookie.includes('uid=')) return;
      const rnd = (crypto && crypto.getRandomValues) ? Array.from(crypto.getRandomValues(new Uint8Array(16))).map(b=>b.toString(16).padStart(2,'0')).join('') : String(Math.random()).slice(2);
      const secureAttr = (location.protocol === 'https:') ? '; Secure' : '';
      document.cookie = "uid="+rnd+"; Max-Age="+(3600*24*365)+"; Path=/; SameSite=Lax"+secureAttr;
    }catch(_){}
  })();
  const $status = document.getElementById('status') || { textContent: '' };
  const $list   = document.getElementById('notes');
  const $form   = document.getElementById('noteForm');

  function fmtISO(s){ try{ return new Date(s).toLocaleString(); }catch(_){ return s||''; } }
  function toast(msg){
    let t = document.getElementById('toast');
    if(!t){
      t = document.createElement('div');
      t.id='toast';
      t.style.cssText='position:fixed;left:50%;bottom:18px;transform:translateX(-50%);background:#111a;color:#eaf2ff;padding:10px 14px;border-radius:10px;border:1px solid #253044;z-index:9999;transition:opacity .25s ease';
      document.body.appendChild(t);
    }
    t.textContent = msg; t.style.opacity='1'; setTimeout(()=>t.style.opacity='0', 1500);
  }
  function noteLink(id){ try{return location.origin+'/?note='+id;}catch(_){return '/?note='+id;} }

  async function apiLike(id){
    const r = await fetch(`/api/notes/${id}/like`, { method:'POST' });
    return r.json();
  }
  async function apiView(id){
    const r = await fetch(`/api/notes/${id}/view`, { method:'POST' });
    return r.json();
  }

  function renderNote(n){
    const li = document.createElement('li');
    li.className = 'note';
    li.id = 'note-'+n.id;
    li.dataset.id = n.id;

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
    const btnReport = document.createElement('button');
    btnReport.textContent = 'Reportar';
    btnReport.addEventListener('click', async (ev)=>{
      ev.stopPropagation(); menu.classList.remove('open');
      try{
        const res = await fetch(`/api/notes/${n.id}/report`, {method:'POST'});
        const data = await res.json();
        if (data.deleted){ li.remove(); toast('Nota eliminada por reportes (5/5)'); }
        else if (data.already_reported){ toast('Ya reportaste'); }
        else if (data.ok){ toast(`Reporte (${data.reports||0}/5)`); }
      }catch(_){ toast('No se pudo reportar'); }
    });
    const btnShare = document.createElement('button');
    btnShare.textContent = 'Compartir';
    btnShare.addEventListener('click', async (ev)=>{
      ev.stopPropagation(); menu.classList.remove('open');
      const url = noteLink(n.id);
      if (navigator.share){ try{ await navigator.share({title:'Nota #'+n.id, url}); return; }catch(_){ } }
      try{ await navigator.clipboard.writeText(url); toast('Enlace copiado'); }
      catch(_){ window.prompt('Copia este enlace:', url); }
    });
    menu.appendChild(btnReport);
    menu.appendChild(btnShare);

    more.addEventListener('click', (ev)=>{ ev.stopPropagation(); menu.classList.toggle('open'); });

    row.appendChild(txt); row.appendChild(more); row.appendChild(menu);

    // barra de acciones
    const bar = document.createElement('div');
    bar.className = 'bar';

    const likeBtn = document.createElement('button');
    likeBtn.className = 'btn-like';
    likeBtn.innerHTML = '♥ Like <span class="like-count">'+(n.likes||0)+'</span>';
    likeBtn.addEventListener('click', async ()=>{
      if (likeBtn.dataset.locked==='1') return; // bloqueo local
      likeBtn.dataset.locked='1';
      try{
        const data = await apiLike(n.id);
        if (data.already_liked){ toast('Ya te gusta'); }
        if (typeof data.likes === 'number'){
          likeBtn.querySelector('.like-count').textContent = data.likes;
        }
      }catch(_){ likeBtn.dataset.locked='0'; toast('Error al dar like'); }
    });

    const views = document.createElement('span');
    views.className = 'views';
    views.innerHTML = '👁 <span class="view-count">'+(n.views||0)+'</span>';

    bar.appendChild(likeBtn);
    bar.appendChild(views);

    const meta = document.createElement('div');
    meta.className = 'meta';
    meta.textContent = `id #${n.id} · ${fmtISO(n.timestamp)} · expira: ${fmtISO(n.expires_at)}`;

    li.appendChild(row);
    li.appendChild(bar);
    li.appendChild(meta);

    // Observador de vistas (una vez)
    if ('IntersectionObserver' in window){
      const io = new IntersectionObserver(async entries=>{
        for (const e of entries){
          if (e.isIntersecting && !li.dataset.viewed){
            li.dataset.viewed='1';
            try{
              const data = await apiView(n.id);
              if (typeof data.views === 'number'){
                const vc = li.querySelector('.view-count');
                if (vc) vc.textContent = data.views;
              }
            }catch(_){}
            io.disconnect();
          }
        }
      }, {threshold: 0.5});
      io.observe(li);
    }else{
      // Fallback: marcar vista al crear
      apiView(n.id).then(data=>{
        if (typeof data.views === 'number'){
          const vc = li.querySelector('.view-count');
          if (vc) vc.textContent = data.views;
        }
      }).catch(()=>{});
    }

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

  if ($form){
    $form.addEventListener('submit', async (ev)=>{
      ev.preventDefault();
      const fd = new FormData($form);
      try{
        const r = await fetch('/api/notes', { method:'POST', body: fd });
        if (!r.ok) throw new Error('HTTP '+r.status);
        await fetchNotes();
        $form.reset();
        const h = document.getElementById('hours'); if (h) h.value = 24;
      }catch(e){ alert('No se pudo publicar: '+e.message); }
    });
  }

  // cierra menús al click fuera
  document.addEventListener('click', ()=> {
    document.querySelectorAll('.note .menu.open').forEach(el => el.classList.remove('open'));
  });

  // scroll a ?note=ID
  try{
    const id = new URLSearchParams(location.search).get('note');
    if (id){
      setTimeout(()=>{ const el = document.getElementById('note-'+id); if (el) el.scrollIntoView({behavior:'smooth', block:'center'}); }, 150);
    }
  }catch(_){}
/* fetchNotes() -> reemplazado por paginación */
})();


/* === Paginación por cursor (after_id + limit) === */
(() => {
  const $list = document.getElementById('notes');
  const $btn  = document.getElementById('loadMore');
  if (!$list || !$btn) return;

  let after = null;
  const LIMIT = 10;

  async function fetchPage(opts = { append: false }) {
    try {
      const qs = new URLSearchParams({ limit: String(LIMIT) });
      if (after) qs.set('after_id', after);

      const res = await fetch('/api/notes?' + qs.toString());
      const data = await res.json();

      if (!opts.append) $list.innerHTML = '';
      data.forEach(n => $list.appendChild(renderNote(n)));

      const next = res.headers.get('X-Next-After');
      after = next && next.trim() ? next.trim() : null;
      $btn.hidden = !after;
      $btn.style.display = after ? 'block' : 'none';
    } catch (e) {
      console.error('pagination fetchPage failed:', e);
    }
  }

  // Primera carga
  fetchPage({ append: false });

  // Botón cargar más
  $btn.addEventListener('click', () => fetchPage({ append: true }));

  // Al publicar una nota, recargar primera página (si existe el form)
  try {
    const $form = document.getElementById('noteForm');
    if ($form) {
      $form.addEventListener('submit', () => {
        after = null;
        setTimeout(() => fetchPage({ append: false }), 200);
      });
    }
  } catch (_) {}
})();

