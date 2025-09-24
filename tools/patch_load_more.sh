#!/usr/bin/env bash
set -euo pipefail

# 1) JS: anexar módulo de "Cargar más" (idempotente)
APP="backend/frontend/js/app.js"
if [[ ! -f "$APP" ]]; then
  echo "No existe $APP"; exit 1
fi

if ! grep -q 'p12SetupLoadMore' "$APP"; then
  cat >> "$APP" <<'JS'

/* === paste12: Load More (con wrap fallback) ================================= */
(() => {
  function q(s, r=document){ return r.querySelector(s); }
  function qa(s, r=document){ return [...r.querySelectorAll(s)]; }

  function findNotesList(){
    return q('#notes-list') ||
           q('ul.notes') ||
           q('section ul') ||
           q('main ul') ||
           qa('[data-note-id], .note, .note-card').map(el => el.parentElement).find(Boolean) ||
           null;
  }
  async function fetchPage(opts={}){
    const limit  = opts.limit ?? 20;
    const before = opts.before;
    const ps = new URLSearchParams({ active_only:'1', limit:String(limit), wrap:'1' });
    if (before) ps.set('before_id', String(before));
    try{
      const r = await fetch('/api/notes?' + ps.toString());
      const j = await r.json();
      if (Array.isArray(j)) {
        const items = j;
        return {
          items,
          has_more: items.length >= limit,
          next_before_id: items.at(-1)?.id ?? null
        };
      }
      return {
        items: j.items || [],
        has_more: !!j.has_more,
        next_before_id: j.next_before_id ?? (j.items?.at(-1)?.id ?? null)
      };
    }catch(_){ return { items:[], has_more:false, next_before_id:null }; }
  }
  function esc(s){ return (s ?? '').toString().replace(/&/g,'&amp;').replace(/</g,'&lt;'); }
  function fmt(iso){ try{ return new Date(iso).toLocaleString(); }catch{ return iso||''; } }

  function makeItem(n){
    const li = document.createElement('li');
    li.className = 'note';
    li.dataset.noteId = String(n.id);
    li.id = 'note-'+n.id;
    li.innerHTML = `
      <div class="note-text">${esc(n.text)}</div>
      <div class="meta"><small>
        #${n.id} &nbsp; ts: ${fmt(n.timestamp)} &nbsp; expira: ${fmt(n.expires_at)} &nbsp;
        ❤ ${n.likes|0} &nbsp; 👁 ${n.views|0} &nbsp; 🚩 ${n.reports|0}
      </small></div>`;
    return li;
  }

  async function setup(){
    const list = findNotesList();
    if (!list) return;

    // Contenedor y botón al **final** del bloque de notas
    let wrap = document.getElementById('load-more');
    if (!wrap){
      wrap = document.createElement('div');
      wrap.id = 'load-more';
      wrap.className = 'load-more';
      wrap.innerHTML = `<button type="button" class="btn-more">Cargar más</button><span class="hint" style="margin-left:8px;"></span>`;
      (list.parentElement || document.body).appendChild(wrap);
    }
    const btn  = wrap.querySelector('.btn-more');
    const hint = wrap.querySelector('.hint');

    let busy = false;
    async function onClick(){
      if (busy) return;
      busy = true; btn.disabled = true; hint.textContent = 'Cargando…';

      const last = qa('[data-note-id], [id^="note-"]', list).pop();
      const id = last?.dataset?.noteId || (last?.id?.match(/note-(\d+)/)?.[1]);
      const {items, has_more} = await fetchPage({ before: id ? Number(id) : undefined, limit: 20 });

      for (const n of items){
        if (list.querySelector(`[data-note-id="${n.id}"]`)) continue; // evita duplicados
        list.appendChild(makeItem(n));
      }
      // añade menú ⋮ si está disponible
      window.p12Enhance?.();

      if (!has_more || items.length === 0) wrap.style.display = 'none';
      hint.textContent = '';
      btn.disabled = false; busy = false;
    }
    btn.addEventListener('click', onClick);

    // Exponer ganchos para smokes
    window.p12SetupLoadMore = setup;
    window.p12LoadMoreClick = onClick;
  }

  if (document.readyState === 'loading'){
    document.addEventListener('DOMContentLoaded', setup);
  } else {
    setup();
  }
})();
JS
  echo "[+] JS anexado en $APP"
else
  echo "[=] JS ya incluído (p12SetupLoadMore)"
fi

# 2) CSS: estilos del botón (idempotente) en actions.css
CSS="backend/frontend/css/actions.css"
[[ -f "$CSS" ]] || touch "$CSS"
if ! grep -q '.load-more' "$CSS"; then
  cat >> "$CSS" <<'CSS'
/* === paste12: botón "Cargar más" ===================== */
.load-more{ display:flex; justify-content:center; margin:12px 0 24px; }
.load-more .btn-more{
  padding:10px 14px; border-radius:10px; border:1px solid #ddd;
  background:#fff; cursor:pointer;
}
.load-more .btn-more:hover{ background:#f3f3f3; }
@media (prefers-color-scheme: dark){
  .load-more .btn-more{ border-color:#2b2f3a; background:#19202a; color:#e7ecf3; }
  .load-more .btn-more:hover{ background:#1e2631; }
}
CSS
  echo "[+] CSS añadido en $CSS"
else
  echo "[=] CSS ya presente (.load-more)"
fi

git add "$APP" "$CSS" >/dev/null 2>&1 || true
git commit -m "feat(ui): botón 'Cargar más' con wrap/before_id (fallback) y estilos mínimos" >/dev/null 2>&1 || true
git push origin main >/dev/null 2>&1 || true
echo "✓ Patch comprometido (o ya estaba)"
