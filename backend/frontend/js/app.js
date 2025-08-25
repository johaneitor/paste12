(() => {
  const $ = (s, r=document) => r.querySelector(s);
  const $$ = (s, r=document) => [...r.querySelectorAll(s)];

  function uiError(msg) {
    let wrap = $('#notes-error');
    if (!wrap) {
      wrap = document.createElement('div');
      wrap.id = 'notes-error';
      wrap.style.cssText = 'margin:12px 0;padding:10px;border-radius:8px;background:#3b2a2a;color:#ffe;'
    }
    wrap.textContent = msg;
    ($('#list') || document.body).prepend(wrap);
  }

  function esc(s){return (s??'').replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]))}

  async function fetchNotes() {
    try {
      const r = await fetch('/api/notes?limit=20', { headers: { 'Accept':'application/json' }});
      if (!r.ok) throw new Error('HTTP '+r.status);
      const j = await r.json();
      return Array.isArray(j) ? j : [];
    } catch (e) {
      console.error('notes fetch failed', e);
      uiError('No pude cargar las notas (reintentá recargar).');
      return [];
    }
  }

  function ensureListContainer() {
    let list = $('#list');
    if (!list) {
      list = document.createElement('div');
      list.id = 'list';
      document.body.appendChild(list);
    }
    let ul = $('#notes', list);
    if (!ul) {
      ul = document.createElement('ul');
      ul.id = 'notes';
      list.appendChild(ul);
    }
    return ul;
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
        <div class="meta">#${n.id}
          &nbsp;•&nbsp; ♥ ${n.likes} &nbsp;👁 ${n.views} &nbsp;🚩 ${n.reports}
        </div>`;
      ul.appendChild(li);
    }
    // enganchar menú ⋮ si está disponible
    window.p12Enhance?.();
  }

  async function boot() {
    try {
      const list = await fetchNotes();
      render(list);
    } catch (e) {
      console.error('boot failed', e);
      uiError('Error inesperado en la UI.');
    }
  }

  // Capturar errores globales (para que no “desaparezcan”)
  window.addEventListener('error', ev => uiError('JS: ' + (ev?.message || 'error')));

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
