#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
cd "$(dirname "$0")"
ts=$(date +%s)

# Backups
[ -f frontend/index.html ] && cp -p frontend/index.html "frontend/index.html.bak.$ts" || true
[ -f frontend/css/styles.css ] && cp -p frontend/css/styles.css "frontend/css/styles.css.bak.$ts" || true

mkdir -p frontend/js

# 1) JS: mostrar vistas + sumar una vez por sesión
cat > frontend/js/views_counter.js <<'JS'
(function(){
  const SEEN_KEY = (id)=>`p12:viewed:${id}`;
  const NOTES_SEL = '#notes, [data-notes], #list, main, body';

  // map de id -> {views,...} del listado actual
  const cache = new Map();
  let fetching = false;

  function getCurrentPage(){
    const u = new URL(location.href);
    const p = parseInt(u.searchParams.get('page')||'1',10);
    return isNaN(p)||p<1 ? 1 : p;
  }

  async function hydrateCache(){
    if (fetching) return;
    fetching = true;
    try{
      const page = getCurrentPage();
      const r = await fetch(`/api/notes?page=${page}`);
      const j = await r.json();
      (j.items||[]).forEach(n => cache.set(String(n.id), n));
    }catch(e){ console.warn('[views] no se pudo hidratar', e); }
    finally{ fetching = false; }
  }

  function getIdFromCard(card){
    return card.getAttribute('data-note')
      || card.getAttribute('data-note-id')
      || (card.dataset ? (card.dataset.note || card.dataset.id) : null)
      || (card.id && card.id.startsWith('n-') ? card.id.slice(2) : null)
      || null;
  }

  function ensureMetrics(card){
    let m = card.querySelector('.p12-metrics');
    if (!m){
      m = document.createElement('div');
      m.className = 'p12-metrics';
      m.innerHTML = `<span class="p12-views" title="Vistas">👁 0</span>`;
      card.appendChild(m);
    }
    return m;
  }

  function setViews(card, count){
    const span = card.querySelector('.p12-views');
    if (span) span.textContent = `👁 ${count}`;
  }

  async function addViewOnce(id, card){
    try{
      if (sessionStorage.getItem(SEEN_KEY(id))) return; // ya sumado en esta sesión
      const res = await fetch(`/api/notes/${id}/view`, {method:'POST'});
      const j = await res.json();
      setViews(card, j.views ?? '?');
      sessionStorage.setItem(SEEN_KEY(id), '1');
    }catch(e){
      console.warn('[views] fallo al sumar', e);
    }
  }

  async function process(container){
    // hidratar cache una sola vez por corrida
    if (cache.size === 0) await hydrateCache();

    container.querySelectorAll('[data-note], [data-note-id], .note-card, article, li').forEach(card=>{
      const id = getIdFromCard(card);
      if (!id) return;
      card.style.position = card.style.position || 'relative';
      ensureMetrics(card);
      // si sabemos la cifra desde cache del listado, muéstrala
      if (cache.has(String(id))) setViews(card, cache.get(String(id)).views ?? 0);
      // suma 1 vez por sesión en primera visualización
      addViewOnce(id, card);
    });
  }

  document.addEventListener('DOMContentLoaded', ()=>{
    const container = document.querySelector(NOTES_SEL);
    if(!container) return;
    process(container);

    // Observa cambios (paginación, nuevas notas)
    const mo = new MutationObserver(()=>{
      process(container);
    });
    mo.observe(container, {childList:true, subtree:true});
    console.log('[views_counter] activo');
  });
})();
JS

# 2) CSS: ubicar el contador de vistas
if ! grep -q '.p12-metrics' frontend/css/styles.css 2>/dev/null; then
cat >> frontend/css/styles.css <<'CSS'

/* --- Métricas (vistas) en tarjeta --- */
.p12-metrics{
  position:absolute; bottom:8px; right:8px;
  background:#0b1530cc; color:#cfe3ff;
  padding:6px 8px; border-radius:8px;
  font-size:12px; display:flex; gap:10px;
  align-items:center; border:1px solid #274a8a66;
}
.p12-metrics .p12-views{ opacity:0.9; }
CSS
fi

# 3) Inyectar el script en index.html
if ! grep -q 'js/views_counter.js' frontend/index.html; then
  perl -0777 -pe 's#</body>#  <script src="js/views_counter.js?v='"$ts"'"></script>\n</body>#i' -i frontend/index.html
fi

# 4) Commit + push (Render redeploy)
git add frontend/js/views_counter.js frontend/css/styles.css frontend/index.html
git commit -m "feat(views): contador visible por nota + suma 1x por sesión; sin recargar backend" || true
git push -u origin "$(git rev-parse --abbrev-ref HEAD)"

echo "✅ Vistas listas. Abre tu sitio con /?v=$ts para limpiar caché del navegador."
