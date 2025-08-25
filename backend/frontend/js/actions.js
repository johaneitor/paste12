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
