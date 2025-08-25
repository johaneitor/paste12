(() => {
  const $  = (s, r=document) => r.querySelector(s);
  const $$ = (s, r=document) => [...r.querySelectorAll(s)];

  function uiError(msg) {
    let wrap = $('#notes-error');
    if (!wrap) {
      wrap = document.createElement('div');
      wrap.id = 'notes-error';
      wrap.style.cssText = 'margin:12px 0;padding:10px;border-radius:8px;background:#3b2a2a;color:#ffe;';
      (document.querySelector('#list') || document.body).prepend(wrap);
    }
    wrap.textContent = msg;
  }
  const esc = (s)=> (s??'').replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));

  // Crea el compositor si no lo trajo el HTML
  function ensureComposer() {
    if (document.querySelector('#composer')) return;
    const section = document.createElement('section');
    section.id = 'composer';
    section.className = 'card';
    section.innerHTML = `
      <h2>Nueva nota</h2>
      <form id="composer-form" style="display:block; gap:12px;">
        <textarea id="note-text" rows="4" placeholder="Escribí tu nota…" style="width:100%;"></textarea>
        <div style="display:flex; gap:12px; align-items:center; flex-wrap:wrap;">
          <label>Expira en (horas):
            <input id="hours" type="number" min="1" max="168" value="24" style="width:5.5rem;">
          </label>
          <button id="publish" type="submit">Publicar</button>
        </div>
      </form>
    `;
    const first = document.body.firstElementChild;
    if (first) document.body.insertBefore(section, first.nextSibling);
    else document.body.appendChild(section);

    const form  = section.querySelector('#composer-form');
    const ta    = section.querySelector('#note-text');
    const hours = section.querySelector('#hours');

    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const text = (ta.value || '').trim();
      const h = parseInt(hours.value || '24', 10) || 24;
      if (!text) { ta.focus(); return; }
      try {
        const r = await fetch('/api/notes', {
          method: 'POST',
          headers: { 'Content-Type':'application/json' },
          body: JSON.stringify({ text, hours: h })
        });
        const j = await r.json().catch(()=>({}));
        if (!r.ok || !j?.id) throw new Error('create failed');
        ta.value = '';
        await loadAndRender();
        window.p12Enhance?.();
      } catch (err) {
        console.error('publish failed', err);
        uiError('No se pudo publicar la nota.');
      }
    });
  }

  function ensureListContainer() {
    let holder = $('#list'); if (!holder) { holder = document.createElement('div'); holder.id = 'list'; document.body.appendChild(holder); }
    let ul = $('#notes', holder); if (!ul) { ul = document.createElement('ul'); ul.id = 'notes'; holder.appendChild(ul); }
    return ul;
  }

  async function fetchNotes() {
    try {
      const r = await fetch('/api/notes?limit=20', { headers: { 'Accept':'application/json' }});
      if (!r.ok) throw new Error('HTTP '+r.status);
      const j = await r.json();
      return Array.isArray(j) ? j : [];
    } catch (e) {
      console.error('notes fetch failed', e);
      uiError('No pude cargar las notas.');
      return [];
    }
  }

  function deriveId(noteEl){
    const ds = noteEl?.dataset || {};
    if (ds.noteId) return parseInt(ds.noteId,10);
    if (noteEl?.id){ const m = noteEl.id.match(/(\d+)/); if (m) return parseInt(m[1],10); }
    return null;
  }

  function render(list) {
    const ul = ensureListContainer();
    ul.innerHTML = '';
    if (!list.length) {
      const li = document.createElement('li');
      li.innerHTML = '<em>No hay notas todavía.</em>';
      ul.appendChild(li);
      return;
    }
    for (const n of list) {
      const li = document.createElement('li');
      li.className = 'note';
      li.dataset.noteId = String(n.id);
      li.id = 'note-' + n.id;
      li.innerHTML = `
        <div class="note-text">${esc(n.text)}</div>
        <div class="meta">
          <span class="sep">#${n.id}</span>
          <button class="like-btn" data-act="like" aria-label="Me gusta">
            <span class="heart" aria-hidden="true">♥</span>
            <span class="count">${n.likes}</span>
          </button>
          <span class="sep">·</span>
          <span class="views">👁 <span class="count">${n.views}</span></span>
          <span class="sep">·</span>
          <span class="reports">🚩 <span class="count">${n.reports}</span></span>
        </div>`;
      ul.appendChild(li);
    }
  }

  async function loadAndRender() {
    const list = await fetchNotes();
    render(list);
  }

  // Delegación para clicks de like
  async function onNotesClick(e){
    const btn = e.target.closest?.('.like-btn');
    if (!btn) return;
    const note = btn.closest('.note');
    const id = deriveId(note);
    if (!id) return;

    // estado UI
    btn.classList.add('liking');
    try{
      const r = await fetch(`/api/notes/${id}/like`, { method:'POST' });
      const j = await r.json().catch(()=>({}));
      if (!r.ok) throw new Error('like failed');
      const newCount = (j && typeof j.likes === 'number') ? j.likes :
                       (parseInt(btn.querySelector('.count')?.textContent || '0',10)+1);
      const countEl = btn.querySelector('.count');
      if (countEl) countEl.textContent = String(newCount);
      btn.classList.add('liked');
    }catch(err){
      console.error(err);
      uiError('No se pudo poner like.');
    }finally{
      btn.classList.remove('liking');
    }
  }

  async function boot() {
    try {
      ensureComposer();
      const ul = ensureListContainer();
      // engancho una sola vez
      if (!ul._p12LikeBound) { ul.addEventListener('click', onNotesClick); ul._p12LikeBound = true; }
      await loadAndRender();
      window.p12Enhance?.();
    } catch (e) {
      console.error('boot failed', e);
      uiError('Error inesperado en la UI.');
    }
  }

  window.addEventListener('error', ev => uiError('JS: ' + (ev?.message || 'error')));
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
