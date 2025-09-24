#!/usr/bin/env bash
set -euo pipefail
T="$(mktemp)"
cat > "$T" <<'HTML'
<!doctype html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="p12-safe-shim" content="v1">
<title>Paste12 — Safe UI</title>
<style>
  body {font: 15px/1.45 system-ui, -apple-system, Segoe UI, Roboto, Arial, sans-serif; margin:0; padding:16px;}
  header{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-bottom:12px}
  textarea{width:100%;min-height:96px;padding:8px}
  button{padding:6px 10px;cursor:pointer}
  .note{border:1px solid #eee; border-radius:8px; padding:10px; margin:8px 0}
  .meta{color:#666;font-size:12px;display:flex;gap:12px}
  #more{display:block;margin:12px auto}
  .hide{display:none}
</style>
<script>
(async () => {
  // opcional: desregistrar SW viejo si se abre con ?nosw=1
  try {
    if (new URLSearchParams(location.search).get('nosw') === '1' && 'serviceWorker' in navigator) {
      const rs = await navigator.serviceWorker.getRegistrations(); rs.forEach(r => r.unregister());
      if (navigator.serviceWorker.controller) navigator.serviceWorker.controller.postMessage({type:'BUST'});
    }
  } catch {}

  const $ = sel => document.querySelector(sel);
  const api = {
    async list(url) {
      const r = await fetch(url || '/api/notes?limit=5', {credentials:'include'});
      const link = r.headers.get('Link');
      const next = (link && /<([^>]+)>;\s*rel="next"/i.exec(link)) ? RegExp.$1 : null;
      const data = await r.json().catch(() => ({ok:false}));
      return {data, next};
    },
    async get(id) {
      const r = await fetch(`/api/notes/${id}`, {credentials:'include'});
      return r.ok ? r.json() : {ok:false};
    },
    async like(id){ return fetch(`/api/notes/${id}/like`, {method:'POST'}).then(r=>r.json()).catch(()=>({ok:false})); },
    async view(id){ return fetch(`/api/notes/${id}/view`, {method:'POST'}).then(r=>r.json()).catch(()=>({ok:false})); },
    async publish(text) {
      // 1) JSON
      try {
        const r = await fetch('/api/notes', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({text})});
        if (r.ok) return r.json();
      } catch {}
      // 2) FORM fallback
      const body = new URLSearchParams({text});
      const r2 = await fetch('/api/notes', {method:'POST', headers:{'Content-Type':'application/x-www-form-urlencoded'}, body});
      return r2.json().catch(()=>({ok:false}));
    }
  };

  function noteHTML(it){
    const ts = it.timestamp ? new Date(it.timestamp).toLocaleString() : '';
    return `
      <div class="note" data-id="${it.id}">
        <div class="text">${(it.text||'').replace(/[&<>]/g,s=>({ '&':'&amp;','<':'&lt;','>':'&gt;' })[s])}</div>
        <div class="meta">
          <span>#${it.id}</span><span>${ts}</span>
          <span>❤ <b class="likes">${it.likes||0}</b></span>
          <span>👁 <b class="views">${it.views||0}</b></span>
          <span><a class="share" href="${location.origin}/?id=${it.id}&nosw=1">Compartir</a></span>
          <button class="btn-like">Like</button>
          <button class="btn-view">View</button>
        </div>
      </div>`;
  }

  function bindDelegation() {
    $('#feed').addEventListener('click', async (ev) => {
      const b = ev.target.closest('button'); if(!b) return;
      const card = ev.target.closest('.note'); if(!card) return;
      const id = card.getAttribute('data-id');
      if (b.classList.contains('btn-like')) {
        const res = await api.like(id);
        if (res && 'likes' in res) card.querySelector('.likes').textContent = res.likes;
      } else if (b.classList.contains('btn-view')) {
        const res = await api.view(id);
        if (res && 'views' in res) card.querySelector('.views').textContent = res.views;
      }
    }, false);
  }

  let NEXT = null;
  async function load(initialUrl) {
    const {data, next} = await api.list(initialUrl);
    if (data && data.items) {
      const frag = document.createDocumentFragment();
      data.items.forEach(it => {
        const div = document.createElement('div');
        div.innerHTML = noteHTML(it);
        frag.appendChild(div.firstElementChild);
      });
      $('#feed').appendChild(frag);
      NEXT = next;
      $('#more').classList.toggle('hide', !NEXT);
    }
  }

  async function boot() {
    bindDelegation();
    // publicar
    $('#pub').addEventListener('submit', async (e) => {
      e.preventDefault();
      const text = $('#text').value.trim();
      if (text.length < 20) { alert('Texto demasiado corto'); return; }
      const res = await api.publish(text);
      if (res && res.ok && res.item) {
        $('#text').value = '';
        $('#feed').insertAdjacentHTML('afterbegin', noteHTML(res.item));
        try { await api.view(res.item.id); } catch {}
      } else {
        alert('No se pudo publicar (intenta más tarde)');
      }
    });

    $('#more').addEventListener('click', () => { if (NEXT) load(NEXT); });

    // modo nota única (?id=)
    const id = new URLSearchParams(location.search).get('id');
    if (id && /^\d+$/.test(id)) {
      document.title = `Nota #${id} — Paste12`;
      $('header .home').classList.remove('hide');
      const res = await api.get(id);
      if (res && res.ok && res.item) {
        $('#feed').innerHTML = noteHTML(res.item);
        try { await api.view(id); } catch {}
        $('#more').classList.add('hide');
        return;
      }
    }
    await load();
  }

  document.addEventListener('DOMContentLoaded', boot);
})();
</script>
<body>
  <header>
    <strong>Paste12</strong>
    <a class="home hide" href="/?nosw=1">← Volver al inicio</a>
    <small style="opacity:.6">safe-shim v1</small>
  </header>

  <form id="pub">
    <textarea id="text" placeholder="Escribe tu nota (≥ 20 caracteres)..."></textarea>
    <div style="margin-top:8px">
      <button type="submit">Publicar</button>
      <button type="button" id="more">Ver más</button>
    </div>
  </form>

  <div id="feed"></div>
</body>
HTML
for f in backend/static/index.html frontend/index.html; do
  mkdir -p "$(dirname "$f")"; cp -f "$T" "$f"
  echo "escrito $f"
done
rm -f "$T"
