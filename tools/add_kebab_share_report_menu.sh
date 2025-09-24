#!/usr/bin/env bash
set -euo pipefail

mkdir -p backend/frontend/js backend/frontend/css

# --- CSS del menú ---
cat > backend/frontend/css/actions.css <<'CSS'
/* Posicionamiento genérico: funciona con .note, .note-card o [data-note-id] */
.note, .note-card, [data-note-id] { position: relative; }

.note-menu { position: absolute; top: .5rem; right: .5rem; z-index: 30; }
.note-menu .kebab {
  background: transparent; border: 0; cursor: pointer; padding: 4px 6px;
  font-size: 20px; line-height: 1; border-radius: 8px;
}
.note-menu .kebab:hover { background: rgba(0,0,0,.06); }
.note-menu .kebab:focus { outline: 2px solid #888; }

.note-menu .panel {
  position: absolute; top: 30px; right: 0;
  background: #fff; border: 1px solid #ddd; border-radius: 10px;
  box-shadow: 0 10px 24px rgba(0,0,0,.15);
  min-width: 180px; display: none; overflow: hidden;
}
.note-menu .panel.show { display: block; }

.note-menu .item {
  display: block; width: 100%; padding: 10px 12px; text-align: left;
  background: none; border: 0; cursor: pointer; font: inherit;
}
.note-menu .item:hover { background: #f5f5f5; }

/* Toast minimalista */
.toast {
  position: fixed; left: 50%; bottom: 24px; transform: translateX(-50%);
  background: rgba(20,20,20,.95); color: #fff; padding: 10px 14px;
  border-radius: 10px; font-size: 14px; z-index: 9999;
  box-shadow: 0 10px 22px rgba(0,0,0,.25);
}
CSS

# --- JS del menú ---
cat > backend/frontend/js/actions.js <<'JS'
(function () {
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
    // 1) data-note-id / data-id
    const ds = noteEl.dataset || {};
    if (ds.noteId) return parseInt(ds.noteId, 10);
    if (ds.id) return parseInt(ds.id, 10);
    // 2) algún descendiente con data-id
    const inner = noteEl.querySelector?.('[data-note-id],[data-id]');
    if (inner) {
      const d = inner.dataset || {};
      if (d.noteId) return parseInt(d.noteId, 10);
      if (d.id) return parseInt(d.id, 10);
    }
    // 3) id="note-123" u "n-123"
    if (noteEl.id) {
      let m = noteEl.id.match(/(?:^|-)note-(\d+)$/i) || noteEl.id.match(/(?:^|-)n-(\d+)$/i);
      if (m) return parseInt(m[1], 10);
    }
    return null;
  }

  async function getNoteText(id, noteEl) {
    // intenta obtener del DOM si hay .note-text / [data-text]
    const domText = noteEl?.querySelector?.('.note-text,[data-text]')?.textContent?.trim();
    if (domText) return domText;
    // si no, pide a la API
    try {
      const r = await fetch(`/api/notes/${id}`);
      if (!r.ok) throw 0;
      const j = await r.json();
      return j.text || `Nota #${id}`;
    } catch { return `Nota #${id}`; }
  }

  async function doShare(id, noteEl) {
    const text = await getNoteText(id, noteEl);
    const url = `${location.origin}/?id=${id}`; // deep link simple
    if (navigator.share) {
      try { await navigator.share({ text, url }); return toast('Compartido'); }
      catch (e) { /* cancelado */ }
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

    // Toggle panel
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      if (state.openPanel && state.openPanel !== panel) state.openPanel.classList.remove('show');
      panel.classList.toggle('show');
      btn.setAttribute('aria-expanded', panel.classList.contains('show') ? 'true' : 'false');
      state.openPanel = panel.classList.contains('show') ? panel : null;
    });

    // Acciones
    wrap.addEventListener('click', (e) => {
      const a = e.target.closest?.('[data-act]');
      if (!a) return;
      e.stopPropagation();
      panel.classList.remove('show');
      if (a.dataset.act === 'share')   doShare(id, noteEl);
      if (a.dataset.act === 'report')  doReport(id);
    });

    // Cerrar al click fuera
    document.addEventListener('click', (e) => {
      if (!panel.classList.contains('show')) return;
      if (!wrap.contains(e.target)) {
        panel.classList.remove('show');
        btn.setAttribute('aria-expanded', 'false');
        if (state.openPanel === panel) state.openPanel = null;
      }
    });

    // Inserta al principio para que quede “en la esquina”
    noteEl.insertBefore(wrap, noteEl.firstChild);
  }

  function enhance(noteEl) {
    if (!noteEl || state.enhanced.has(noteEl)) return;
    const id = deriveId(noteEl);
    if (!id) return; // no podemos crear menú sin id
    // Evita duplicados si el template ya lo trae
    if (noteEl.querySelector?.('.note-menu')) {
      state.enhanced.add(noteEl); return;
    }
    buildMenu(noteEl, id);
    state.enhanced.add(noteEl);
  }

  function enhanceAll() {
    document.querySelectorAll('[data-note-id], .note-card, .note').forEach(enhance);
  }

  // Observa DOM por si el listado se vuelve a renderizar
  const obs = new MutationObserver((mut) => {
    for (const m of mut) {
      m.addedNodes?.forEach?.(n => {
        if (n.nodeType === 1) {
          if (closestNoteEl(n)) enhance(closestNoteEl(n));
          n.querySelectorAll?.('[data-note-id], .note-card, .note').forEach(enhance);
        }
      });
    }
  });

  window.addEventListener('DOMContentLoaded', () => {
    enhanceAll();
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
JS

# --- Inyectar en index.html ---
INDEX="backend/frontend/index.html"
if [ -f "$INDEX" ]; then
  # CSS antes de </head>
  if ! grep -q '/css/actions.css' "$INDEX"; then
    sed -i 's#</head>#  <link rel="stylesheet" href="/css/actions.css">\n</head>#' "$INDEX"
  fi
  # JS antes de </body>
  if ! grep -q '/js/actions.js' "$INDEX"; then
    sed -i 's#</body>#  <script src="/js/actions.js"></script>\n</body>#' "$INDEX"
  fi
else
  echo "No se encontró $INDEX. ¿Tu frontend vive en otra ruta?" >&2
fi

git add backend/frontend/css/actions.css backend/frontend/js/actions.js backend/frontend/index.html || true
git commit -m "feat(frontend): menú ⋮ en notas (Compartir/Reportar) + toast" || true
git push origin main
echo "Listo. Tras el deploy de Render, recargá con Ctrl+F5."
