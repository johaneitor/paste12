(function () {
  'use strict';

  const state = { enhanced: new WeakSet(), openPanel: null };

  function toast(msg) {
    const t = document.createElement('div');
    t.className = 'toast';
    t.textContent = msg;
    document.body.appendChild(t);
    setTimeout(() => { t.remove(); }, 1700);
  }

  function closestNoteEl(el) {
    return el?.closest?.('[data-note-id], .note-card, .note');
  }

  function deriveId(noteEl) {
    if (!noteEl) return null;
    // 1) data-note-id / data-id
    const ds = noteEl.dataset || {};
    if (ds.noteId && /^\d+$/.test(ds.noteId)) return parseInt(ds.noteId, 10);
    if (ds.id && /^\d+$/.test(ds.id)) return parseInt(ds.id, 10);

    // 2) algún descendiente con data-id
    const inner = noteEl.querySelector?.('[data-note-id],[data-id]');
    if (inner) {
      const d = inner.dataset || {};
      if (d.noteId && /^\d+$/.test(d.noteId)) return parseInt(d.noteId, 10);
      if (d.id && /^\d+$/.test(d.id)) return parseInt(d.id, 10);
    }

    // 3) id="note-123" u "n-123"
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
    } catch {
      return `Nota #${id}`;
    }
  }

  async function doShare(id, noteEl) {
    const text = await getNoteText(id, noteEl);
    const url = `${location.origin}/?id=${id}`;
    if (navigator.share) {
      try {
        await navigator.share({ text, url });
        toast('Compartido');
        return;
      } catch {
        /* cancelado o no permitido: fallback */
      }
    }
    try {
      await navigator.clipboard.writeText(`${text}\n${url}`);
      toast('Copiado al portapapeles');
    } catch {
      toast('No se pudo compartir');
    }
  }

  async function doReport(id) {
    try {
      const r = await fetch(`/api/notes/${id}/report`, { method: 'POST' });
      if (!r.ok) throw 0;
      const j = await r.json();
      toast(j?.ok ? 'Reportado' : 'Reportado');
    } catch {
      toast('Error al reportar');
    }
  }

  function buildMenu(noteEl, id) {
    const wrap = document.createElement('div');
    wrap.className = 'note-menu';
    wrap.innerHTML = `
      <button class="kebab" type="button" aria-haspopup="menu" aria-expanded="false" aria-label="Abrir menú">⋯</button>
      <div class="panel" role="menu">
        <button class="item" data-act="share"  role="menuitem">Compartir</button>
        <button class="item" data-act="report" role="menuitem">Reportar</button>
      </div>
    `;
    const btn = wrap.querySelector('.kebab');
    const panel = wrap.querySelector('.panel');

    function closePanel() {
      panel.classList.remove('show', 'up');
      btn.setAttribute('aria-expanded', 'false');
      if (state.openPanel === panel) state.openPanel = null;
    }

    function openPanel() {
      if (state.openPanel && state.openPanel !== panel) {
        state.openPanel.classList.remove('show', 'up');
      }
      panel.classList.add('show');
      btn.setAttribute('aria-expanded', 'true');
      state.openPanel = panel;

      // Reposicionar si se sale de viewport por abajo (fallback simple)
      panel.classList.remove('up');
      const rect = panel.getBoundingClientRect();
      if (rect.bottom > window.innerHeight) {
        panel.classList.add('up');
      }
    }

    // Toggle panel
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      if (panel.classList.contains('show')) {
        closePanel();
      } else {
        openPanel();
      }
    });

    // Acciones
    wrap.addEventListener('click', (e) => {
      const a = e.target.closest?.('[data-act]');
      if (!a) return;
      e.stopPropagation();
      closePanel();
      if (a.dataset.act === 'share')   doShare(id, noteEl);
      if (a.dataset.act === 'report')  doReport(id);
    });

    // Cerrar al click fuera
    document.addEventListener('click', (e) => {
      if (!panel.classList.contains('show')) return;
      if (!wrap.contains(e.target)) {
        closePanel();
      }
    });

    // Cerrar con Esc
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && panel.classList.contains('show')) {
        closePanel();
      }
    });

    // Inserta al principio para que quede “en la esquina”
    noteEl.insertBefore(wrap, noteEl.firstChild);
  }

  function enhance(noteEl) {
    if (!noteEl || state.enhanced.has(noteEl)) return;
    const id = deriveId(noteEl);
    if (!id) return; // sin id no se construye menú
    if (noteEl.querySelector?.('.note-menu')) {
      state.enhanced.add(noteEl);
      return;
    }
    buildMenu(noteEl, id);
    state.enhanced.add(noteEl);
  }

  function enhanceAll() {
    document.querySelectorAll('[data-note-id], .note-card, .note').forEach(enhance);
  }

  // Fallback opcional: si las tarjetas no traen data-note-id y no hay forma de derivar,
  // intentamos etiquetar por orden usando la API (mejor que nada).
  async function tagDomByOrder() {
    const containerNodes = Array.from(document.querySelectorAll('[data-note-id], .note-card, .note'));
    if (containerNodes.length === 0) return false;

    const missing = containerNodes.filter(el => !deriveId(el));
    if (missing.length === 0) return false;

    try {
      const r = await fetch(`/api/notes?limit=${containerNodes.length}`);
      if (!r.ok) return false;
      const list = await r.json();
      containerNodes.forEach((el, i) => {
        const n = list[i];
        if (n && !el.dataset.noteId) {
          el.dataset.noteId = String(n.id);
          if (!el.id) el.id = `note-${n.id}`;
          el.classList.add('note');
        }
      });
      return true;
    } catch {
      return false;
    }
  }

  // Observa DOM por si el listado se vuelve a renderizar
  const obs = new MutationObserver((mut) => {
    for (const m of mut) {
      m.addedNodes?.forEach?.(n => {
        if (n.nodeType === 1) {
          const card = closestNoteEl(n);
          if (card) enhance(card);
          n.querySelectorAll?.('[data-note-id], .note-card, .note').forEach(enhance);
        }
      });
    }
  });

  window.addEventListener('DOMContentLoaded', async () => {
    enhanceAll();
    // Fallback de etiquetado por orden si aún no se pudo
    const didTag = await tagDomByOrder();
    if (didTag) enhanceAll();

    obs.observe(document.body, { childList: true, subtree: true });

    // Deep link ?id=123 -> desplazar a la nota
    const p = new URLSearchParams(location.search);
    const deeplink = p.get('id');
    if (deeplink) {
      const target =
        document.querySelector(`[data-note-id="${deeplink}"]`) ||
        document.getElementById(`note-${deeplink}`) ||
        document.querySelector(`.note-card[id$="-${deeplink}"]`);
      if (target) target.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
  });
})();
