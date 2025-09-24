#!/usr/bin/env bash
set -euo pipefail
ROOT="$(pwd)"
ROUTES="$ROOT/backend/routes.py"
IDX="$ROOT/backend/frontend/index.html"
ACTJS="$ROOT/backend/frontend/js/actions.js"

# ---- Backend: inyectar helper de cleanup y extender list_notes ----
if [[ -f "$ROUTES" ]]; then
python - "$ROUTES" <<'PY'
import re, sys, datetime as _dt
p = sys.argv[1]
code = open(p, 'r', encoding='utf-8').read()
orig = code

# ensure imports (datetime/sqlalchemy) near flask import
if 'import datetime as _dt' not in code:
    code = re.sub(r'(from flask import[^\n]+\n)', r'\1import datetime as _dt\n', code, count=1)
if 'import sqlalchemy as sa' not in code:
    code = re.sub(r'(from flask import[^\n]+\n(?:import datetime as _dt\n)?)', r'\1import sqlalchemy as sa\n', code, count=1)

# helper cleanup oportunista (si no existe)
if '_maybe_cleanup_expired' not in code:
    code += r"""

_last_cleanup_ts = 0
def _maybe_cleanup_expired(db, Note, LikeLog=None, ReportLog=None, ViewLog=None, max_batch=200):
    """ "Elimina notas expiradas (y logs) con rate limit simple (60s)." """
    global _last_cleanup_ts
    import time
    now = time.time()
    if now - _last_cleanup_ts < 60:
        return 0
    _last_cleanup_ts = now
    cutoff = _dt.datetime.utcnow()
    try:
        ids = [r.id for r in db.session.query(Note.id, ).filter(Note.expires_at != None, Note.expires_at <= cutoff).limit(max_batch).all()]
        if not ids:
            return 0
        for Log in (LikeLog, ReportLog, ViewLog):
            if Log is None: continue
            db.session.query(Log).filter(Log.note_id.in_(ids)).delete(synchronize_session=False)
        db.session.query(Note).filter(Note.id.in_(ids)).delete(synchronize_session=False)
        db.session.commit()
        return len(ids)
    except Exception:
        db.session.rollback()
        return 0
"""
# parchear list_notes: before_id, wrap=1, active_only y orden por id desc
def repl_list_notes(m):
    return r"""@api.route("/notes")
def list_notes():
    from flask import request, jsonify
    from backend import db  # type: ignore
    try:
        from backend.models import Note, LikeLog, ReportLog, ViewLog  # type: ignore
    except Exception:
        # fallback si los nombres difieren
        from backend.models import Note  # type: ignore
        LikeLog = ReportLog = ViewLog = None  # type: ignore

    _maybe_cleanup_expired(db, Note, LikeLog, ReportLog, ViewLog)

    try:
        limit = min(int(request.args.get("limit", 20)), 100)
    except Exception:
        limit = 20
    before_id = request.args.get("before_id", type=int)
    wrap = request.args.get("wrap", type=int) == 1
    active_only = request.args.get("active_only", type=int) != 0

    q = db.session.query(Note)
    if active_only:
        now = _dt.datetime.utcnow()
        q = q.filter((Note.expires_at == None) | (Note.expires_at > now))
    if before_id:
        q = q.filter(Note.id < before_id)
    q = q.order_by(Note.id.desc()).limit(limit + 1)
    rows = q.all()

    has_more = len(rows) > limit
    rows = rows[:limit]
    next_before_id = rows[-1].id if rows else None

    def ser(n):
        return {
            "id": n.id,
            "text": getattr(n, "text", ""),
            "timestamp": getattr(n, "timestamp", None),
            "expires_at": getattr(n, "expires_at", None),
            "likes": getattr(n, "likes", 0),
            "views": getattr(n, "views", 0),
            "reports": getattr(n, "reports", 0),
        }
    items = [ser(n) for n in rows]
    if wrap:
        return jsonify({"items": items, "has_more": bool(has_more), "next_before_id": next_before_id})
    return jsonify(items)
"""

# Encontrar bloque de list_notes existente
code = re.sub(
    r"@api\.route\([\"']\/notes[\"']\)\s*def\s+list_notes\(\):(.|\n)*?return[^\n]+",
    repl_list_notes,
    code, flags=re.DOTALL
)

if code != orig:
    open(p, 'w', encoding='utf-8').write(code)
    print("routes.py actualizado")
else:
    print("routes.py ya estaba actualizado")
PY
else
  echo "No existe $ROUTES"; exit 1
fi

# ---- Frontend: helper 'Cargar más' en actions.js (idempotente) ----
mkdir -p "$(dirname "$ACTJS")"
touch "$ACTJS"
if ! grep -q 'p12InitLoadMore' "$ACTJS"; then
cat >> "$ACTJS" <<'JS'

// ====== Load More (paginación por before_id) ======
(function(){
  const state = {pageSize: 20, loading:false, done:false};
  function $(s, r=document){ return r.querySelector(s); }
  function $all(s, r=document){ return [...r.querySelectorAll(s)]; }
  function deriveId(el){
    if (!el) return null;
    const d = el.dataset||{};
    if (d.noteId) return +d.noteId;
    if (d.id) return +d.id;
    if (el.id){
      const m = el.id.match(/(?:^|-)note-(\d+)$/i) || el.id.match(/(?:^|-)n-(\d+)$/i);
      if (m) return +m[1];
    }
    const inner = el.querySelector?.('[data-note-id],[data-id]');
    if (inner) return deriveId(inner);
    return null;
  }
  function listRoot(){
    return $('#notes-list') || document.querySelector('ul.notes') || document.querySelector('main ul') || document.querySelector('section ul') || document.querySelector('ol') || document.querySelector('ul');
  }
  function lastShownId(){
    let min = null;
    $all('[data-note-id], .note, .note-card, li', listRoot()||document).forEach(el=>{
      const id = deriveId(el); if (id) min = (min===null)?id:Math.min(min,id);
    });
    return min;
  }
  function escapeHtml(s){return (s??'').replace(/[&<>"']/g,m=>({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[m]));}
  function makeLi(n){
    const li = document.createElement('li');
    li.className='note';
    li.dataset.noteId = n.id;
    li.id = 'note-'+n.id;
    li.innerHTML = `
      <div class="note-text">${escapeHtml(n.text)}</div>
      <div class="note-stats stats">
        <small>#${n.id}&nbsp;ts: ${String(n.timestamp||'').replace('T',' ')}&nbsp;&nbsp;expira: ${String(n.expires_at||'').replace('T',' ')}</small>
        <span class="stat like">❤ ${n.likes||0}</span>
        <span class="stat view">👁 ${n.views||0}</span>
        <span class="stat flag">🚩 ${n.reports||0}</span>
      </div>`;
    return li;
  }
  async function loadMore(){
    if (state.loading || state.done) return;
    state.loading = true;
    const root = listRoot(); if (!root) { state.loading=false; return; }
    const last = lastShownId();
    const url = `/api/notes?wrap=1&active_only=1&limit=${state.pageSize}` + (last?`&before_id=${last}`:'');
    try{
      const r = await fetch(url);
      const j = await r.json();
      const items = j.items || (Array.isArray(j)? j : []);
      items.forEach(n => root.appendChild(makeLi(n)));
      window.p12Enhance?.();              // menú ⋮
      window.p12InitRemaining?.();        // contador restante
      state.done = !j.has_more || items.length < state.pageSize;
      if (state.done) document.getElementById('load-more-btn')?.setAttribute('disabled','true');
    }catch(e){ /* noop */ }
    state.loading = false;
  }
  function ensureButton(){
    if (document.getElementById('load-more-btn')) return;
    const root = listRoot(); if (!root) return;
    const container = document.createElement('div');
    container.style.textAlign='center'; container.style.margin='16px 0 32px';
    container.innerHTML = `<button id="load-more-btn" class="btn" type="button">Cargar más</button>`;
    (root.parentElement || document.body).appendChild(container);
    document.getElementById('load-more-btn').addEventListener('click', loadMore);
  }
  function init(){ ensureButton(); }
  window.p12InitLoadMore = init;
  document.addEventListener('DOMContentLoaded', init);
})();
JS
fi

# Bust de cache mínimo si existe index.html
if [[ -f "$IDX" ]]; then
  sed -i 's#/js/actions.js#&?v=pg1#' "$IDX" || true
fi

git add "$ROUTES" "$ACTJS" "$IDX" >/dev/null 2>&1 || true
git commit -m "feat(api+ui): paginación before_id (wrap=1), filtro activos y cleanup oportunista; botón Cargar más" >/dev/null 2>&1 || true
git push origin main >/dev/null 2>&1 || true
echo "✓ Patch aplicado (o ya estaba)."
