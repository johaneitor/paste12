(function () {
  const $status = document.getElementById('status');
  const $list = document.getElementById('notes');
  const $form = document.getElementById('noteForm');

  function fmtISO(s) {
    try { return new Date(s).toLocaleString(); } catch { return s; }
  }

  async function fetchNotes() {
    $status.textContent = 'cargando…';
    try {
      const res = await fetch('/api/notes?page=1');
      const data = await res.json();
      $list.innerHTML = '';
      data.forEach(n => {
        const li = document.createElement('li');
        li.className = 'note';
        li.innerHTML = `
          <div class="txt">${n.text ?? ''}</div>
          <div class="meta">
            <span>id #${n.id}</span>
            <span> · </span>
            <span>${fmtISO(n.timestamp)}</span>
            <span> · expira: ${fmtISO(n.expires_at)}</span>
          </div>
        `;
        $list.appendChild(li);
      });
      $status.textContent = 'ok';
    } catch (e) {
      console.error(e);
      $status.textContent = 'error cargando';
    }
  }

  $form.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const fd = new FormData($form);
    try {
      const res = await fetch('/api/notes', { method: 'POST', body: fd });
      if (!res.ok) throw new Error('HTTP ' + res.status);
      // refrescar
      await fetchNotes();
      $form.reset();
      document.getElementById('hours').value = 24;
    } catch (e) {
      alert('No se pudo publicar la nota: ' + e.message);
    }
  });

  fetchNotes();
})();
