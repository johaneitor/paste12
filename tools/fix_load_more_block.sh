#!/usr/bin/env bash
set -euo pipefail
APP="backend/frontend/js/app.js"
CSS="backend/frontend/css/actions.css"

[[ -f "$APP" ]] || { echo "No existe $APP"; exit 1; }

python - "$APP" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
src = p.read_text(encoding="utf-8")

if "p12SetupLoadMore" in src:
    print("app.js: bloque Load More ya presente")
else:
    block = """
/* === paste12: Load More (BEGIN) ================================= */
(() => {
  function q(s,r=document){return r.querySelector(s);}
  function qa(s,r=document){return [...r.querySelectorAll(s)];}

  function findNotesList(){
    return q('#notes-list') || q('ul.notes') || q('main ul') ||
           qa('[data-note-id], .note, .note-card').map(el=>el.parentElement).find(Boolean) || null;
  }
  async function fetchPage(opts={}){
    const limit = opts.limit ?? 20;
    const before = opts.before;
    const ps = new URLSearchParams({active_only:'1', limit:String(limit), wrap:'1'});
    if (before) ps.set('before_id', String(before));
    try{
      const r = await fetch('/api/notes?'+ps.toString());
      const j = await r.json();
      if (Array.isArray(j)) {
        const items = j;
        return { items, has_more: items.length >= limit, next_before_id: items.at(-1)?.id ?? null };
      }
      return { items: j.items || [], has_more: !!j.has_more, next_before_id: j.next_before_id ?? (j.items?.at(-1)?.id ?? null) };
    }catch(_){ return { items:[], has_more:false, next_before_id:null }; }
  }
  function esc(s){ return (s??'').toString().replace(/&/g,'&amp;').replace(/</g,'&lt;'); }
  function fmt(iso){ try{ return new Date(iso).toLocaleString(); }catch{ return iso||''; } }
  function makeItem(n){
    const li = document.createElement('li');
    li.className = 'note';
    li.dataset.noteId = String(n.id);
    li.id = 'note-'+n.id;
    li.innerHTML = `<div class="note-text">${esc(n.text)}</div>
      <div class="meta"><small>
        #${n.id} &nbsp; ts: ${fmt(n.timestamp)} &nbsp; expira: ${fmt(n.expires_at)} &nbsp;
        ❤ ${n.likes||0} &nbsp; 👁 ${n.views||0} &nbsp; 🚩 ${n.reports||0}
      </small></div>`;
    return li;
  }
  async function setup(){
    const list = findNotesList();
    if (!list) return;
    let wrap = document.getElementById('load-more');
    if (!wrap){
      wrap = document.createElement('div');
      wrap.id = 'load-more';
      wrap.className = 'load-more';
      wrap.innerHTML = `<button type="button" class="btn-more">Cargar más</button><span class="hint" style="margin-left:8px;"></span>`;
      (list.parentElement || document.body).appendChild(wrap);
    }
    const btn = wrap.querySelector('.btn-more');
    const hint = wrap.querySelector('.hint');
    let busy = false;
    async function onClick(){
      if (busy) return;
      busy = true; btn.disabled = true; hint.textContent = 'Cargando…';
      const last = qa('[data-note-id], [id^="note-"]', list).pop();
      const id = last?.dataset?.noteId || (last?.id?.match(/note-(\\d+)/)?.[1]);
      const {items, has_more} = await fetchPage({ before: id ? Number(id) : undefined, limit: 20 });
      for (const n of items){
        if (list.querySelector(\`[data-note-id="\${n.id}"]\`)) continue;
        list.appendChild(makeItem(n));
      }
      window.p12Enhance?.();
      if (!has_more || items.length === 0) wrap.style.display = 'none';
      hint.textContent = ''; btn.disabled = false; busy = false;
    }
    btn.addEventListener('click', onClick);
    window.p12SetupLoadMore = setup;
    window.p12LoadMoreClick = onClick;
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', setup); else setup();
})();
/* === paste12: Load More (END) =============================== */
"""
    p.write_text(src.rstrip()+"\n"+block, encoding="utf-8")
    print("app.js: bloque Load More AÑADIDO")
PY

# CSS idempotente
[[ -f "$CSS" ]] || touch "$CSS"
grep -q '.load-more' "$CSS" 2>/dev/null || cat >>"$CSS" <<'CSS'
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

git add "$APP" "$CSS" >/dev/null 2>&1 || true
git commit -m "fix(ui): añade bloque 'Cargar más' (p12SetupLoadMore) + CSS si faltan" >/dev/null 2>&1 || true
git push origin main >/dev/null 2>&1 || true
echo "✓ Commit & push hecho"
