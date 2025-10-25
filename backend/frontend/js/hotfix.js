(function(){
  function fmtCountdown(expISO){
    if(!expISO) return "";
    const now = Date.now();
    const ms  = Date.parse(expISO) - now;
    const s = Math.max(0, Math.floor(ms/1000));
    const d = Math.floor(s/86400), r1 = s - d*86400;
    const h = Math.floor(r1/3600), r2 = r1 - h*3600;
    const m = Math.floor(r2/60), x = r2 - m*60;
    if (d>0) return `${d}d ${h}h`;
    if (h>0) return `${h}h ${m}m`;
    if (m>0) return `${m}m ${x}s`;
    return `${x}s`;
  }

  function startCountdownLoop(){
    function tick(){
      document.querySelectorAll('.countdown[data-expires-at]').forEach(el=>{
        const iso = el.getAttribute('data-expires-at');
        el.textContent = fmtCountdown(iso);
        const ttl = (Date.parse(iso) - Date.now())/1000;
        el.classList.toggle('danger', ttl<=3600);
        el.classList.toggle('warn', ttl<=86400 && ttl>3600);
        el.title = `Expira: ${new Date(iso).toLocaleString()}`;
      });
    }
    tick(); setInterval(tick, 1000);
  }

  async function api(path, opts){
    const r = await fetch(path, Object.assign({headers:{'Content-Type':'application/json'}}, opts||{}));
    if(!r.ok) throw new Error(`HTTP ${r.status}`);
    return r.json();
  }

  function escapeHtml(s){
    return (s??'').toString().replace(/[&<>"]|'/g, m => ({
      '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;'
    })[m]);
  }

  function buildCard(n){
    const art = document.createElement('article');
    art.className = 'note-card';
    art.setAttribute('data-note', n.id);
    art.innerHTML = `
      <div class="note-body">${escapeHtml(n.text)}</div>
      <div class="note-meta">
        <span class="countdown" data-expires-at="${n.expires_at||""}"></span>
        <div class="spacer"></div>
        <button class="btn-like" data-id="${n.id}" aria-label="Me gusta">❤️ <b>${n.likes||0}</b></button>
        <span class="views" title="Vistas">👁️ ${(n.views||0)}</span>
      </div>
    `;
    const btn = art.querySelector('.btn-like');
    btn.addEventListener('click', async (ev)=>{
      ev.preventDefault();
      try{
        const j = await api(`/api/notes/${n.id}/like`, {method:'POST'});
        btn.querySelector('b').textContent = j.likes ?? (parseInt(btn.querySelector('b').textContent||'0',10)+1);
      }catch(e){ console.warn('like failed', e); }
    });
    return art;
  }

  async function loadAndRender(page=1){
    try{
      const limit = Math.max(1, 20);
      const data = await api(`/api/notes?wrap=1&active_only=1&limit=${limit}`);
      const items = Array.isArray(data?.items)? data.items : (Array.isArray(data?.notes)? data.notes : (Array.isArray(data)? data : []));
      const list = document.getElementById('notes') || document.querySelector('[data-notes], #list, main');
      if(!list) return;
      list.innerHTML = '';
      items.forEach(n => list.appendChild(buildCard(n)));
      if(items.length>0) startCountdownLoop();
      console.log(`[hotfix] renderizadas ${items.length} notas`);
    }catch(e){
      console.warn('[hotfix] fallo cargando notas', e);
    }
  }

  function wireForm(){
    const form = document.getElementById('form') || document.querySelector('form[data-note-form]');
    if(!form) return;
    form.addEventListener('submit', async (ev)=>{
      try{
        const t = (form.querySelector('textarea, [name="text"]')||{}).value?.trim() || '';
        if(!t) return;
        ev.preventDefault();
        const hoursSel = form.querySelector('[name="duration"], [name="hours"]');
        let body = { text: t };
        if (hoursSel) {
          const v = hoursSel.value || hoursSel.getAttribute('value') || '';
          body.duration = v; // el backend acepta "12h","1d","7d"
        }
        await api('/api/notes', {method:'POST', body: JSON.stringify(body)});
        (form.querySelector('textarea, [name="text"]')||{}).value = '';
        await loadAndRender(1);
      }catch(e){ console.warn('[hotfix] submit fallo', e); }
    }, {once:true});
  }

  // Sólo corre si la lista está vacía después de que cargó la página (no pisa tu app.js)
  document.addEventListener('DOMContentLoaded', ()=>{
    const list = document.getElementById('notes') || document.querySelector('[data-notes], #list, main');
    setTimeout(()=>{
      if (!list) return;
      const empty = !list.children || list.children.length===0;
      if (empty) {
        console.log('[hotfix] lista vacía: aplicando renderer alternativo');
        wireForm();
        loadAndRender(1);
      } else {
        console.log('[hotfix] lista no vacía: no se aplica');
      }
    }, 400);
  });
})();
