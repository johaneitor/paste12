#!/usr/bin/env bash
set -euo pipefail

# Elige el index a parchear
pick_index() {
  for f in backend/static/index.html frontend/index.html index.html; do
    [ -f "$f" ] && { echo "$f"; return; }
  done
  echo "✗ No encontré index.html (backend/static/, frontend/ o raíz)">&2; exit 2
}
IDX="$(pick_index)"
BAK="${IDX}.cohesion.bak"

# Backup sólo si no existe
[ -f "$BAK" ] || cp -f "$IDX" "$BAK"

# Inyecta shim entre marcadores (idempotente)
if grep -q 'COHESION-SHIM START' "$IDX"; then
  echo "OK: shim ya presente en $IDX (no se duplica)"
  exit 0
fi

cat >> "$IDX" <<'HTML'

<!-- COHESION-SHIM START -->
<script>
(function(){
  const Q = new URLSearchParams(location.search);

  // (1) Opcional: desregistrar SW/caches al abrir con ?nosw=1 o ?debug=1
  if (Q.get('nosw')==='1' || Q.get('debug')==='1') {
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.getRegistrations().then(rs => rs.forEach(r=>r.unregister()));
    }
    if (window.caches && caches.keys) {
      caches.keys().then(keys => keys.forEach(k => caches.delete(k)));
    }
  }

  // (2) Matar banner de actualización si aparece
  function killUpdate(){
    const b = document.getElementById('deploy-stamp-banner');
    if (b) b.remove();
  }
  killUpdate();
  new MutationObserver(()=>killUpdate()).observe(document.documentElement, {childList:true,subtree:true});

  // (3) Feed principal unificado
  function $(q){ return document.querySelector(q); }
  const FEED = $('#list, .list, [data-notes], [data-feed], #notes, #feed') ||
               (function(){ const d=document.createElement('div'); d.id='list'; document.body.appendChild(d); return d; })();

  // Si algún shim crea #feed aparte, mover su contenido a FEED
  new MutationObserver(muts=>{
    for (const m of muts) for (const n of m.addedNodes) {
      if (n.nodeType===1 && n.id==='feed' && n!==FEED) {
        while (n.firstChild) FEED.appendChild(n.firstChild);
        n.remove();
      }
    }
  }).observe(document.body,{childList:true,subtree:true});

  // (4) Marcar nodo de texto para “ver más”
  function markTextNodes(){
    document.querySelectorAll('article.note').forEach(a=>{
      const first = a.querySelector(':scope > div:first-child');
      if (first && !first.hasAttribute('data-text')) first.setAttribute('data-text','1');
    });
  }
  markTextNodes();

  // (5) Decorador “ver más” idempotente
  function enhanceCard(a){
    const t = a.querySelector('[data-text]');
    if (!t || a._enhanced) return;
    const full = t.textContent || '';
    if (full.length <= 140) { a._enhanced = true; return; }
    const short = full.slice(0,120)+'…';
    const b = document.createElement('button');
    b.type='button'; b.textContent='Ver más'; b.className='btn-more';
    t.dataset.full = full; t.textContent = short; t.after(b);
    b.addEventListener('click', ()=>{
      if (t.classList.toggle('expanded')) { t.textContent = t.dataset.full; b.textContent='Ver menos'; }
      else { t.textContent = short; b.textContent='Ver más'; }
    });
    a._enhanced = true;
  }
  document.querySelectorAll('article.note').forEach(enhanceCard);

  // Observar tarjetas nuevas en FEED para aplicar “ver más”
  new MutationObserver(muts=>{
    muts.forEach(m=>m.addedNodes.forEach(n=>{
      if (n.nodeType!==1) return;
      if (n.matches && n.matches('article.note')) { markTextNodes(); enhanceCard(n); }
      n.querySelectorAll && n.querySelectorAll('article.note').forEach(x=>{ markTextNodes(); enhanceCard(x); });
    }));
  }).observe(FEED,{childList:true,subtree:true});

  // (6) Paginación con keyset (Link / X-Next-Cursor) + dedupe
  const seen = new Set(Array.from(document.querySelectorAll('article.note[data-id]')).map(e=>e.getAttribute('data-id')));
  let nextURL = null;

  async function fetchPage(url) {
    const res = await fetch(url,{headers:{'Accept':'application/json'}});
    nextURL = null;
    const link = res.headers.get('Link');
    const xnext = res.headers.get('X-Next-Cursor');
    if (link) {
      const m = /<([^>]+)>;\s*rel="next"/i.exec(link); if (m) nextURL = m[1];
    } else if (xnext) {
      try { const j = JSON.parse(xnext); if (j.cursor_ts && j.cursor_id) nextURL = `/api/notes?cursor_ts=${encodeURIComponent(j.cursor_ts)}&cursor_id=${j.cursor_id}`; } catch(_){}
    }
    const j = await res.json();
    return j.items || [];
  }

  function renderItems(items){
    items.forEach(it=>{
      const id = String(it.id);
      if (seen.has(id)) return;
      seen.add(id);
      const art = document.createElement('article');
      art.className='note'; art.setAttribute('data-id', id);
      const textDiv = document.createElement('div');
      textDiv.setAttribute('data-text','1');
      textDiv.textContent = it.text || '(sin texto)';
      art.appendChild(textDiv);
      const meta = document.createElement('div');
      meta.className='meta';
      meta.textContent = `#${id} · ❤ ${it.likes ?? 0} · 👁 ${it.views ?? 0}`;
      art.appendChild(meta);
      const actions = document.createElement('div');
      actions.className='actions';
      actions.innerHTML = `
        <button type="button" data-like="${id}">like</button>
        <button type="button" data-share="${id}">compartir</button>
        <button type="button" data-report="${id}">reportar</button>`;
      art.appendChild(actions);
      FEED.appendChild(art);
      enhanceCard(art);
    });
  }

  // Delegación de acciones (para nuevas páginas también)
  document.addEventListener('click', async (e)=>{
    const t = e.target;
    if (!(t instanceof Element)) return;
    const id = t.getAttribute('data-like') || t.getAttribute('data-report') || t.getAttribute('data-share');
    if (!id) return;
    try {
      if (t.hasAttribute('data-like')) {
        await fetch(`/api/notes/${id}/like`, {method:'POST'});
        t.textContent = 'liked ✓';
      } else if (t.hasAttribute('data-report')) {
        await fetch(`/api/notes/${id}/report`, {method:'POST'});
        t.textContent = 'reportado ✓';
      } else if (t.hasAttribute('data-share')) {
        const u = `${location.origin}/n/${id}`;
        try { await navigator.clipboard.writeText(u); t.textContent='copiado ✓'; } catch(_){ t.textContent=u; }
      }
    } catch(_) {}
  }, {capture:true});

  // Botón “Cargar más” bajo el feed
  const more = document.createElement('button');
  more.id='load-more'; more.type='button'; more.textContent='Cargar más';
  FEED.after(more);
  more.addEventListener('click', async ()=>{
    if (!nextURL) {
      const items = await fetchPage('/api/notes?limit=10');
      renderItems(items);
      if (!nextURL) { more.disabled=true; more.textContent='Sin más'; }
      return;
    }
    const items = await fetchPage(nextURL);
    renderItems(items);
    if (!nextURL) { more.disabled=true; more.textContent='Fin'; }
  });

  // Bootstrap liviano para capturar nextURL (con dedupe)
  (async ()=>{
    const items = await fetchPage('/api/notes?limit=1');
    renderItems(items);
  })();

})();
</script>
<!-- COHESION-SHIM END -->
HTML

echo "patched: shim de cohesión añadido | backup=$(basename "$BAK")"
