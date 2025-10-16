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

/* === paste12: Unified Pagination (BEGIN) ============================ */
(() => {
  const state = { nextUrl: null, loading: false, limit: 20 };
  const seenIds = new Set();

  function q(sel, r=document){ return r.querySelector(sel); }
  function qa(sel, r=document){ return [...r.querySelectorAll(sel)]; }

  function listRoot(){
    return q('#notes-list') || q('ul.notes') || q('main ul') || q('section ul') || q('ol') || q('ul');
  }

  function makeLi(n){
    const li = document.createElement('li');
    li.className = 'note';
    li.dataset.noteId = String(n.id);
    li.id = 'note-'+n.id;
    li.innerHTML = `
      <div class="note-text">${esc(n.text)}</div>
      <div class="note-stats stats">
        <small>#${n.id}&nbsp;ts: ${String(n.timestamp||'').replace('T',' ')}&nbsp;&nbsp;expira: ${String(n.expires_at||'').replace('T',' ')}</small>
        <span class="stat like">❤ ${n.likes||0}</span>
        <span class="stat view">👁 ${n.views||0}</span>
        <span class="stat flag">🚩 ${n.reports||0}</span>
      </div>`;
    return li;
  }

  function ensureMore(){
    let wrap = document.getElementById('p12-more');
    if (!wrap){
      wrap = document.createElement('div');
      wrap.id = 'p12-more';
      wrap.className = 'load-more';
      wrap.innerHTML = `<button type="button" class="btn-more" aria-live="polite">Cargar más</button><span class="hint" aria-live="polite" style="margin-left:8px;"></span>`;
      (listRoot()?.parentElement || document.body).appendChild(wrap);
    }
    return wrap;
  }

  function setBtn(stateName){
    const wrap = ensureMore();
    const btn = wrap.querySelector('.btn-more');
    const hint = wrap.querySelector('.hint');
    if (!btn || !hint) return;
    if (stateName === 'idle'){ btn.disabled = false; btn.textContent = 'Cargar más'; hint.textContent = ''; }
    if (stateName === 'loading'){ btn.disabled = true; btn.textContent = 'Cargando…'; hint.textContent = 'Cargando página…'; }
    if (stateName === 'error'){ btn.disabled = false; btn.textContent = 'Reintentar'; hint.textContent = 'Error al cargar'; }
  }

  function showSkeleton(count=3){
    const root = listRoot(); if (!root) return [];
    const nodes = [];
    for (let i=0; i<count; i++){
      const li = document.createElement('li');
      li.className = 'note skeleton';
      li.innerHTML = `<div class="s1"></div><div class="s2"></div>`;
      root.appendChild(li); nodes.push(li);
    }
    return nodes;
  }

  function removeNodes(nodes){ nodes.forEach(n => n && n.remove()); }

  function parseNext(resp, body){
    try{
      const link = resp.headers.get('Link') || resp.headers.get('link');
      if (link){
        const m = /<([^>]+)>;\s*rel="?next"?/i.exec(link);
        if (m) return m[1];
      }
      const xnc = resp.headers.get('X-Next-Cursor');
      if (xnc){
        try{ const xn = JSON.parse(xnc); if (xn && xn.cursor_ts && xn.cursor_id){ return `/api/notes?cursor_ts=${encodeURIComponent(xn.cursor_ts)}&cursor_id=${xn.cursor_id}`; } }catch{}
      }
      const xna = resp.headers.get('X-Next-After');
      if (xna){ return `/api/notes?limit=${state.limit}&after_id=${encodeURIComponent(xna)}`; }
      if (body && body.has_more && body.next_before_id){
        return `/api/notes?wrap=1&active_only=1&limit=${state.limit}&before_id=${body.next_before_id}`;
      }
    }catch{}
    return null;
  }

  async function fetchPage(next){
    if (state.loading) return { ok:false };
    const root = listRoot(); if (!root) return { ok:false };
    state.loading = true; setBtn('loading');
    const sk = showSkeleton(3);
    try{
      const url = next || `/api/notes?wrap=1&active_only=1&limit=${state.limit}`;
      const res = await fetch(url, { headers:{ 'Accept':'application/json' } });
      const body = await res.json().catch(()=>({}));
      const items = Array.isArray(body) ? body : (body.items || []);
      for (const it of items){
        const id = Number(it.id);
        if (!id || seenIds.has(id)) continue;
        seenIds.add(id);
        root.appendChild(makeLi(it));
      }
      window.p12Enhance?.();
      window.p12InitRemaining?.();
      state.nextUrl = parseNext(res, body);
      ensureMore().style.display = state.nextUrl ? '' : 'none';
      setBtn('idle');
      return { ok:true };
    }catch(_){
      setBtn('error');
      return { ok:false };
    }finally{
      removeNodes(sk);
      state.loading = false;
    }
  }

  async function init(){
    const root = listRoot(); if (!root) return;
    ensureMore();
    const wrap = ensureMore();
    const btn = wrap.querySelector('.btn-more');
    if (btn && !btn._p12Bound){ btn.addEventListener('click', () => fetchPage(state.nextUrl)); btn._p12Bound = true; }
    await fetchPage(null);
  }

  window.p12Pager = { init, fetchNext: () => fetchPage(state.nextUrl) };
})();
/* === paste12: Unified Pagination (END) ============================== */
