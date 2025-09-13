#!/usr/bin/env bash
set -euo pipefail
files=()
[ -f backend/static/index.html ] && files+=(backend/static/index.html)
[ -f frontend/index.html ]       && files+=(frontend/index.html)
[ ${#files[@]} -eq 0 ] && { echo "✗ no hay index.html para parchear"; exit 1; }

read -r -d '' SHIM <<"HTML"
<!-- P12 SAFE SHIM v1.1 : start -->
<meta name="p12-safe-shim" content="v1.1">
<script>
(async () => {
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
    async get(id) { const r = await fetch(`/api/notes/${id}`, {credentials:'include'}); return r.ok ? r.json() : {ok:false}; },
    async like(id){ return fetch(`/api/notes/${id}/like`, {method:'POST'}).then(r=>r.json()).catch(()=>({ok:false})); },
    async view(id){ return fetch(`/api/notes/${id}/view`, {method:'POST'}).then(r=>r.json()).catch(()=>({ok:false})); },
    async publish(text) {
      try { const r = await fetch('/api/notes',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({text})}); if (r.ok) return r.json(); } catch {}
      try { const r2 = await fetch('/api/notes',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({text})}); return await r2.json(); } catch { return {ok:false}; }
    }
  };
  const esc = s => (s||'').replace(/[&<>]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));
  function noteHTML(it){
    const ts = it.timestamp ? new Date(it.timestamp).toLocaleString() : '';
    const share = `${location.origin}/?id=${it.id}&nosw=1`;
    return `<article class="note" data-id="${it.id}">
      <div class="text">${esc(it.text)}</div>
      <div class="meta">
        <span>#${it.id}</span><span>${ts}</span>
        <span>❤ <b class="likes">${it.likes||0}</b></span>
        <span>👁 <b class="views">${it.views||0}</b></span>
        <a class="share" href="${share}" rel="noopener">Compartir</a>
        <button class="btn-like" type="button">Like</button>
        <button class="btn-view" type="button">View</button>
      </div>
    </article>`;
  }
  function bindDelegation() {
    const feed = document.getElementById('feed');
    if (!feed) return;
    feed.addEventListener('click', async (ev) => {
      const btn = ev.target.closest('button'); if(!btn) return;
      const card = ev.target.closest('.note'); if(!card) return;
      const id = card.getAttribute('data-id');
      if (btn.classList.contains('btn-like')) {
        const res = await api.like(id);
        if (res && 'likes' in res) card.querySelector('.likes').textContent = res.likes;
      } else if (btn.classList.contains('btn-view')) {
        const res = await api.view(id);
        if (res && 'views' in res) card.querySelector('.views').textContent = res.views;
      }
    }, false);
  }
  const seen = new Set();
  const io = ('IntersectionObserver' in window) ? new IntersectionObserver(entries => {
    entries.forEach(async e => {
      if (!e.isIntersecting) return;
      const card = e.target;
      const id = card.getAttribute('data-id');
      if (!id || seen.has(id)) { io.unobserve(card); return; }
      seen.add(id);
      try { const res = await api.view(id); if (res && 'views' in res) card.querySelector('.views').textContent = res.views; } catch {}
      io.unobserve(card);
    });
  }, {rootMargin:'0px 0px -20% 0px'}) : null;
  const observeCard = card => { if (io) try { io.observe(card); } catch {} };
  let NEXT = null;
  async function load(initialUrl) {
    const st = document.getElementById('status'); if (st) st.textContent = 'Cargando…';
    const {data, next} = await api.list(initialUrl);
    if (data && data.items) {
      const frag = document.createDocumentFragment();
      data.items.forEach(it => { const wrap=document.createElement('div'); wrap.innerHTML = noteHTML(it); frag.appendChild(wrap.firstElementChild); });
      const feed = document.getElementById('feed'); if (feed) feed.appendChild(frag);
      document.querySelectorAll('.note').forEach(observeCard);
      NEXT = next; const more = document.getElementById('more'); if (more) more.classList.toggle('hide', !NEXT);
    }
    const st2 = document.getElementById('status'); if (st2) st2.textContent = NEXT ? 'Más resultados disponibles' : 'Fin del feed';
  }
  async function boot() {
    bindDelegation();
    const form = document.getElementById('pub');
    if (form) form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const ta = document.getElementById('text');
      const btn = document.getElementById('btn-pub');
      const text = (ta && ta.value || '').trim();
      if (text.length < 20) { alert('Texto demasiado corto'); return; }
      if (btn) btn.disabled = true;
      const res = await api.publish(text);
      if (btn) btn.disabled = false;
      if (res && res.ok && res.item) {
        if (ta) ta.value = '';
        const feed = document.getElementById('feed');
        if (feed) { feed.insertAdjacentHTML('afterbegin', noteHTML(res.item)); observeCard(feed.querySelector('.note')); }
        try { await api.view(res.item.id); } catch {}
      } else {
        alert('No se pudo publicar (intenta más tarde)');
      }
    });
    const more = document.getElementById('more'); if (more) more.addEventListener('click', () => { if (NEXT) load(NEXT); });
    const id = new URLSearchParams(location.search).get('id');
    if (id && /^\d+$/.test(id)) {
      document.title = `Nota #${id} — Paste12`;
      document.head.insertAdjacentHTML('beforeend', `<meta name="p12-single" content="\${id}">`);
      const home = document.querySelector('a.home'); if (home) home.classList.remove('hide');
      const st = document.getElementById('status'); if (st) st.textContent = 'Cargando nota…';
      const res = await api.get(id);
      const feed = document.getElementById('feed');
      if (feed && res && res.ok && res.item) {
        feed.innerHTML = noteHTML(res.item);
        observeCard(feed.querySelector('.note')); try { await api.view(id); } catch {}
        if (more) more.classList.add('hide');
        if (st) st.textContent = 'Nota cargada';
        return;
      } else { if (st) st.textContent = 'No encontrada'; return; }
    }
    await load();
  }
  document.addEventListener('DOMContentLoaded', boot);
})();
</script>
<style>
  :root { --fg:#111; --mut:#666; --bd:#eee; }
  body {font: 15px/1.45 system-ui, -apple-system, Segoe UI, Roboto, Arial, sans-serif; margin:0; padding:16px; color:var(--fg);}
  header{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-bottom:12px}
  textarea{width:100%;min-height:96px;padding:8px}
  button{padding:6px 10px;cursor:pointer}
  .note{border:1px solid var(--bd); border-radius:8px; padding:10px; margin:8px 0; background:#fff}
  .meta{color:var(--mut);font-size:12px;display:flex;gap:12px;align-items:center;flex-wrap:wrap}
  #more{display:inline-block;margin-left:8px}
  .hide{display:none}
  .status{font-size:12px;color:var(--mut)}
</style>
<!-- P12 SAFE SHIM v1.1 : end -->
HTML

patch_one() {
  local f="$1"
  [ -f "$f" ] || return 0
  local bak="${f}.bak_$(date -u +%Y%m%d-%H%M%SZ)"
  cp -f "$f" "$bak"
  # quita versiones anteriores del shim (delimitadas por comentarios)
  sed -e '/P12 SAFE SHIM v1\.1 : start/,/P12 SAFE SHIM v1\.1 : end/d' "$bak" > "$f.tmp" || cp -f "$bak" "$f.tmp"
  # asegura <body> y <header>/<form>/<div id="feed">
  if ! grep -qi '<body' "$f.tmp"; then echo '<body>' >> "$f.tmp"; fi
  if ! grep -qi 'class="home' "$f.tmp"; then
    awk '1; /<body[^>]*>/ {print "  <header>\n    <strong>Paste12</strong>\n    <a class=\"home hide\" href=\"/?nosw=1\">← Inicio</a>\n    <small class=\"status\" id=\"status\" style=\"margin-left:auto;opacity:.7\">Listo</small>\n    <small style=\"opacity:.6\">safe-shim v1.1</small>\n  </header>\n\n  <form id=\"pub\" autocomplete=\"off\">\n    <textarea id=\"text\" placeholder=\"Escribe tu nota (≥ 20 caracteres)…\"></textarea>\n    <div style=\"margin-top:8px\">\n      <button type=\"submit\" id=\"btn-pub\">Publicar</button>\n      <button type=\"button\" id=\"more\" class=\"hide\">Ver más</button>\n    </div>\n  </form>\n\n  <div id=\"feed\"></div>"}' "$f.tmp" > "$f.tmp2"; mv -f "$f.tmp2" "$f.tmp"
  fi
  # inserta SHIM antes de </body> (o al final si no existe)
  if grep -qi '</body>' "$f.tmp"; then
    awk -v block="$SHIM" 'BEGIN{done=0} {if (!done && match(tolower($0), /<\/body>/)) {print block; done=1} print} END{if(!done) print block}' "$f.tmp" > "$f"
  else
    cat "$f.tmp" > "$f"; echo "$SHIM" >> "$f"
  fi
  rm -f "$f.tmp"
  echo "OK: inyectado safe-shim v1.1 en $f | backup=$(basename "$bak")"
}
for f in "${files[@]}"; do patch_one "$f"; done
