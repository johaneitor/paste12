(function () {
  if (window.p12Enhance) return; // evitar doble carga

  const state = { enhanced: new WeakSet(), openPanel: null };

  function toast(msg) {
    const t = document.createElement('div');
    t.className = 'toast';
    t.textContent = msg;
    document.body.appendChild(t);
    setTimeout(() => { t.remove(); }, 1700);
  }

  function closestNoteEl(el) {
    return el.closest?.('[data-note-id], .note-card, .note');
  }

  function deriveId(noteEl) {
    if (!noteEl) return null;
    const ds = noteEl.dataset || {};
    if (ds.noteId) return parseInt(ds.noteId, 10);
    if (ds.id)     return parseInt(ds.id, 10);
    const inner = noteEl.querySelector?.('[data-note-id],[data-id]');
    if (inner) {
      const d = inner.dataset || {};
      if (d.noteId) return parseInt(d.noteId, 10);
      if (d.id)     return parseInt(d.id, 10);
    }
    if (noteEl.id) {
      let m = noteEl.id.match(/(?:^|-)note-(\d+)$/i) || noteEl.id.match(/(?:^|-)n-(\d+)$/i);
      if (m) return parseInt(m[1], 10);
    }
    return null;
  }

  async function getNoteText(id, noteEl) {
    const domText = noteEl?.querySelector?.('.note-text,[data-text]')?.textContent?.trim();
    if (domText) return domText;
    try {
      const r = await fetch(`/api/notes/${id}`);
      if (!r.ok) throw 0;
      const j = await r.json();
      return j.text || `Nota #${id}`;
    } catch { return `Nota #${id}`; }
  }

  async function doShare(id, noteEl) {
    const text = await getNoteText(id, noteEl);
    const url = `${location.origin}/?id=${id}`;
    if (navigator.share) {
      try { await navigator.share({ text, url }); return toast('Compartido'); }
      catch (e) { /* cancelado */ }
    }
    try {
      await navigator.clipboard.writeText(`${text}\n${url}`);
      toast('Copiado al portapapeles');
    } catch { toast('No se pudo compartir'); }
  }

  async function doReport(id) {
    try {
      const r = await fetch(`/api/notes/${id}/report`, { method: 'POST' });
      if (!r.ok) throw 0;
      const j = await r.json();
      toast(j?.ok ? 'Reportado' : 'Reportado');
    } catch { toast('Error al reportar'); }
  }

  function buildMenu(noteEl, id) {
    const wrap = document.createElement('div');
    wrap.className = 'note-menu';
    wrap.innerHTML = `
      <button class="kebab" type="button" aria-haspopup="menu" aria-expanded="false" aria-label="Abrir menú">⋮</button>
      <div class="panel" role="menu">
        <button class="item" data-act="share"  role="menuitem">Compartir</button>
        <button class="item" data-act="report" role="menuitem">Reportar</button>
      </div>
    `;
    const btn = wrap.querySelector('.kebab');
    const panel = wrap.querySelector('.panel');

    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      if (state.openPanel && state.openPanel !== panel) state.openPanel.classList.remove('show');
      panel.classList.toggle('show');
      btn.setAttribute('aria-expanded', panel.classList.contains('show') ? 'true' : 'false');
      state.openPanel = panel.classList.contains('show') ? panel : null;
    });

    wrap.addEventListener('click', (e) => {
      const a = e.target.closest?.('[data-act]');
      if (!a) return;
      e.stopPropagation();
      panel.classList.remove('show');
      if (a.dataset.act === 'share')   doShare(id, noteEl);
      if (a.dataset.act === 'report')  doReport(id);
    });

    document.addEventListener('click', (e) => {
      if (!panel.classList.contains('show')) return;
      if (!wrap.contains(e.target)) {
        panel.classList.remove('show');
        btn.setAttribute('aria-expanded', 'false');
        if (state.openPanel === panel) state.openPanel = null;
      }
    });

    noteEl.insertBefore(wrap, noteEl.firstChild);
  }

  function enhance(noteEl) {
    if (!noteEl || state.enhanced.has(noteEl)) return;
    const id = deriveId(noteEl);
    if (!id) return;
    if (noteEl.querySelector?.('.note-menu')) { state.enhanced.add(noteEl); return; }
    buildMenu(noteEl, id);
    state.enhanced.add(noteEl);
  }

  function enhanceAll() {
    document.querySelectorAll('[data-note-id], .note-card, .note').forEach(enhance);
  }

  // Fallback: etiqueta por orden si el DOM no trae data-note-id
  async function tagDomByOrder() {
    try {
      const r = await fetch('/api/notes?limit=50');
      if (!r.ok) return;
      const list = await r.json();
      const cards = [...document.querySelectorAll('[data-note-id], .note-card, .note, ul li, ol li')];
      let idx = 0;
      for (const el of cards) {
        if (!el.dataset.noteId && list[idx]) {
          el.dataset.noteId = String(list[idx].id);
          if (!el.id) el.id = `note-${list[idx].id}`;
        }
        idx++;
        if (idx >= list.length) break;
      }
    } catch {}
  }

  // Garantiza menús aunque el DOM no tenga attrs
  async function ensureMenus() {
    enhanceAll();
    if (document.querySelectorAll('.note-menu').length === 0) {
      await tagDomByOrder();
      enhanceAll();
    }
  }

  // Observa DOM por re-render
  const obs = new MutationObserver((mut) => {
    for (const m of mut) {
      m.addedNodes?.forEach?.(n => {
        if (n.nodeType === 1) {
          const el = closestNoteEl(n) || n;
          if (el) enhance(el);
          n.querySelectorAll?.('[data-note-id], .note-card, .note').forEach(enhance);
        }
      });
    }
  });

  function boot() {
    ensureMenus();
    obs.observe(document.body, { childList: true, subtree: true });
    const p = new URLSearchParams(location.search);
    const deeplink = p.get('id');
    if (deeplink) {
      const target =
        document.querySelector(`[data-note-id="${deeplink}"]`) ||
        document.getElementById(`note-${deeplink}`) ||
        document.querySelector(`.note-card[id$="-${deeplink}"]`);
      if (target) target.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }

  // Helpers para debugging en consola
  window.p12Enhance = ensureMenus;
  window.p12TagByOrder = tagDomByOrder;
})();

// --- AdSense bootstrap (sin inline) ---
window.p12AdsInit = function() {
  try { (window.adsbygoogle = window.adsbygoogle || []).push({}); } catch(e) {}
};
window.addEventListener('DOMContentLoaded', function() {
  if (document.querySelector('ins.adsbygoogle')) { window.p12AdsInit(); }
});

// ===== Remaining-time enhancer (no intrusivo) =====
(function(){
  const seen = new WeakSet();
  function deriveNoteId(el){
    if (!el) return null;
    const ds = el.dataset||{};
    if (ds.noteId) return +ds.noteId;
    if (ds.id)     return +ds.id;
    if (el.id){
      const m = el.id.match(/(?:^|-)note-(\d+)$/i) || el.id.match(/(?:^|-)n-(\d+)$/i);
      if (m) return +m[1];
    }
    const inner = el.querySelector?.('[data-note-id],[data-id]');
    if (inner) return deriveNoteId(inner);
    return null;
  }
  function ensureTagByOrder(){
    // si el render no marca data-note-id, etiqueta por orden usando /api/notes
    const cards = [...document.querySelectorAll('[data-note-id], .note, .note-card, li')];
    if (cards.some(c => c.dataset.noteId)) return Promise.resolve();
    return fetch('/api/notes?limit=' + cards.length)
      .then(r=>r.ok?r.json():[])
      .then(list=>{
        cards.forEach((el,i)=>{ if (list[i]?.id) el.dataset.noteId = String(list[i].id); });
      }).catch(()=>{});
  }
  function formatLeft(ms){
    if (ms<=0) return 'expirada';
    const s = Math.floor(ms/1000);
    const d = Math.floor(s/86400);
    const h = Math.floor((s%86400)/3600);
    const m = Math.floor((s%3600)/60);
    if (d>0) return `${d}d ${h}h`;
    if (h>0) return `${h}h ${m}m`;
    return `${m}m`;
  }
  function attach(el, expISO){
    if (!expISO || seen.has(el)) return;
    const slot = document.createElement('span');
    slot.className = 'stat time-left';
    slot.style.marginLeft = '8px';
    el.appendChild(slot);
    function tick(){
      const left = new Date(expISO).getTime() - Date.now();
      slot.textContent = '⏳ ' + formatLeft(left);
      slot.title = new Date(expISO).toLocaleString();
    }
    tick(); setInterval(tick, 60000);
    seen.add(el);
  }

  async function hydrate(){
    await ensureTagByOrder();
    // map id -> element that holds stats line (buscamos línea de “expira” o fila de contadores)
    const notes = [...document.querySelectorAll('[data-note-id], .note, .note-card, li')];
    const map = new Map();
    notes.forEach(el=>{
      const id = deriveNoteId(el);
      if (!id) return;
      // heurística: lugar donde están los contadores
      const stats = el.querySelector('.stats, .note-stats') || el.querySelector('small, .badge, .counter')?.parentElement || el;
      map.set(id, stats);
    });
    if (map.size===0) return;

    // pedimos expirations para las visibles
    const ids = [...map.keys()];
    const limit = Math.max(ids.length, 20);
    const list = await fetch('/api/notes?limit='+limit).then(r=>r.json()).catch(()=>[]);
    const byId = new Map(list.map(n=>[n.id, n]));
    ids.forEach(id=>{
      const n = byId.get(id);
      if (n?.expires_at && map.get(id)) attach(map.get(id), n.expires_at);
    });
  }

  window.p12InitRemaining = hydrate;
  document.addEventListener('DOMContentLoaded', hydrate);
})();

// ====== Load More (paginación por before_id) ======
(function(){
  const state = {pageSize: 20, loading:false, done:false};
  function $(s, r=document){ return r.querySelector(s); }
  function $all(s, r=document){ return [...r.querySelectorAll(s)]; }

  function deriveId(el){
    if (!el) return null;
    const d = el.dataset||{};
    if (d.noteId) return +d.noteId;
    if (d.id) return +d.id;
    if (el.id){
      const m = el.id.match(/(?:^|-)note-(\d+)$/i) || el.id.match(/(?:^|-)n-(\d+)$/i);
      if (m) return +m[1];
    }
    const inner = el.querySelector?.('[data-note-id],[data-id]');
    if (inner) return deriveId(inner);
    return null;
  }
  function listRoot(){
    return $('#notes-list') || $('ul.notes') || $('main ul') || $('section ul') || $('ol') || $('ul');
  }
  function lastShownId(){
    let min = null;
    $all('[data-note-id], .note, .note-card, li', listRoot()).forEach(el=>{
      const id = deriveId(el);
      if (id) min = (min===null) ? id : Math.min(min, id);
    });
    return min;
  }
  function escapeHtml(s){return (s??'').replace(/[&<>"']/g,m=>({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[m]));}
  function makeLi(n){
    const li = document.createElement('li');
    li.className='note';
    li.dataset.noteId = n.id;
    li.id = 'note-'+n.id;
    li.innerHTML = `
      <div class="note-text">${escapeHtml(n.text)}</div>
      <div class="note-stats stats">
        <small>#${n.id}&nbsp;ts: ${String(n.timestamp||'').replace('T',' ')}&nbsp;&nbsp;expira: ${String(n.expires_at||'').replace('T',' ')}</small>
        <span class="stat like">❤ ${n.likes||0}</span>
        <span class="stat view">👁 ${n.views||0}</span>
        <span class="stat flag">🚩 ${n.reports||0}</span>
      </div>`;
    return li;
  }
  async function loadMore(){
    if (state.loading || state.done) return;
    state.loading = true;
    const root = listRoot(); if (!root) { state.loading=false; return; }
    const last = lastShownId();
    const url = `/api/notes?wrap=1&active_only=1&limit=${state.pageSize}` + (last?`&before_id=${last}`:'');
    try{
      const r = await fetch(url);
      const j = await r.json();
      const items = j.items || (Array.isArray(j)? j : []);
      items.forEach(n => root.appendChild(makeLi(n)));
      window.p12Enhance?.();              // menucito ⋮
      window.p12InitRemaining?.();        // ⏳ restante
      state.done = !j.has_more || items.length < state.pageSize;
      if (state.done) $('#load-more-btn')?.setAttribute('disabled','true');
    }catch(e){ /* noop */ }
    state.loading = false;
  }
  function ensureButton(){
    // Evita duplicar si ya existe el botón alternativo
    if ($('#load-more-btn') || document.getElementById('load-more')) return;
    const container = document.createElement('div');
    container.style.textAlign='center'; container.style.margin='16px 0 32px';
    container.innerHTML = `<button id="load-more-btn" class="btn" type="button">Cargar más</button>`;
    (listRoot()?.parentElement || document.body).appendChild(container);
    $('#load-more-btn').addEventListener('click', loadMore);
  }
  function init(){ ensureButton(); }
  window.p12InitLoadMore = init;
  document.addEventListener('DOMContentLoaded', init);
})();
