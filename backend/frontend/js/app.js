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
    // Prefer existing #notes-list from HTML; fallback to #notes
    let ul = document.querySelector('#notes-list') || document.querySelector('#notes');
    if (!ul) {
      ul = document.createElement('ul');
      ul.id = 'notes-list';
      (document.getElementById('list') || document.body).appendChild(ul);
    }
    return ul;
  }

  async function fetchNotes() {
    try {
      const r = await fetch('/api/notes?limit=20', { headers: { 'Accept':'application/json' }});
      if (!r.ok) throw new Error('HTTP '+r.status);
      const j = await r.json();
      if (Array.isArray(j)) return j;
      if (j && Array.isArray(j.notes)) return j.notes;
      if (j && Array.isArray(j.items)) return j.items;
      return [];
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
      // AdSense fallback init if actions_menu is not loaded
      try {
        if (document.querySelector('ins.adsbygoogle')) {
          (window.adsbygoogle = window.adsbygoogle || []).push({});
        }
      } catch (_) {}
    } catch (e) {
      console.error('boot failed', e);
      uiError('Error inesperado en la UI.');
    }
  }

  window.addEventListener('error', ev => uiError('JS: ' + (ev?.message || 'error')));
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();

/* === paste12: Load More (BEGIN) ================================= */
(() => {
  function q(s,r=document){return r.querySelector(s);}
  function qa(s,r=document){return [...r.querySelectorAll(s)];}

  function findNotesList(){
    return q('#notes-list') || q('ul.notes') || q('main ul') ||
           qa('[data-note-id], .note, .note-card').map(el=>el.parentElement).find(Boolean) || null;
  }
  async function fetchPage(opts={}){
    const limit = opts.limit ?? 20;
    const before = opts.before;
    const ps = new URLSearchParams({active_only:'1', limit:String(limit), wrap:'1'});
    if (before) ps.set('before_id', String(before));
    try{
      const r = await fetch('/api/notes?'+ps.toString());
      const j = await r.json();
      if (Array.isArray(j)) {
        const items = j;
        return { items, has_more: items.length >= limit, next_before_id: items.at(-1)?.id ?? null };
      }
      return { items: j.items || [], has_more: !!j.has_more, next_before_id: j.next_before_id ?? (j.items?.at(-1)?.id ?? null) };
    }catch(_){ return { items:[], has_more:false, next_before_id:null }; }
  }
  function esc(s){ return (s??'').toString().replace(/&/g,'&amp;').replace(/</g,'&lt;'); }
  function fmt(iso){ try{ return new Date(iso).toLocaleString(); }catch{ return iso||''; } }
  function makeItem(n){
    const li = document.createElement('li');
    li.className = 'note';
    li.dataset.noteId = String(n.id);
    li.id = 'note-'+n.id;
    li.innerHTML = `<div class="note-text">${esc(n.text)}</div>
      <div class="meta"><small>
        #${n.id} &nbsp; ts: ${fmt(n.timestamp)} &nbsp; expira: ${fmt(n.expires_at)} &nbsp;
        ❤ ${n.likes||0} &nbsp; 👁 ${n.views||0} &nbsp; 🚩 ${n.reports||0}
      </small></div>`;
    return li;
  }
  async function setup(){
    const list = findNotesList();
    if (!list) return;
    // Evitar duplicados si otra feature ya insertó botón (hotfix/views/actions)
    if (document.getElementById('load-more-btn')) return;
    let wrap = document.getElementById('load-more');
    if (!wrap){
      wrap = document.createElement('div');
      wrap.id = 'load-more';
      wrap.className = 'load-more';
      wrap.innerHTML = `<button type="button" class="btn-more">Cargar más</button><span class="hint" style="margin-left:8px;"></span>`;
      (list.parentElement || document.body).appendChild(wrap);
    }
    const btn = wrap.querySelector('.btn-more');
    const hint = wrap.querySelector('.hint');
    let busy = false;
    async function onClick(){
      if (busy) return;
      busy = true; btn.disabled = true; hint.textContent = 'Cargando…';
      const last = qa('[data-note-id], [id^="note-"]', list).pop();
      const id = last?.dataset?.noteId || (last?.id?.match(/note-(\d+)/)?.[1]);
      const {items, has_more} = await fetchPage({ before: id ? Number(id) : undefined, limit: 20 });
      for (const n of items){
        if (list.querySelector(`[data-note-id="${n.id}"]`)) continue;
        list.appendChild(makeItem(n));
      }
      window.p12Enhance?.();
      if (!has_more || items.length === 0) wrap.style.display = 'none';
      hint.textContent = ''; btn.disabled = false; busy = false;
    }
    btn.addEventListener('click', onClick);
    window.p12SetupLoadMore = setup;
    window.p12LoadMoreClick = onClick;
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', setup); else setup();
})();
/* === paste12: Load More (END) =============================== */
