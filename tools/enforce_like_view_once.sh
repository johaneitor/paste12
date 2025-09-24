#!/usr/bin/env bash
set -Eeuo pipefail

backup(){ [ -f "$1" ] && cp -f "$1" "$1.bak.$(date +%s)" || true; }

echo "→ Backups"
backup backend/models.py
backup backend/routes.py
backup frontend/js/app.js

############################################
# 1) MODELOS: LikeLog y ViewLog
############################################
python - <<'PY'
from pathlib import Path
p = Path("backend/models.py")
s = p.read_text(encoding="utf-8")

if "class LikeLog" not in s or "class ViewLog" not in s:
    # asegurar imports
    if "from datetime import datetime" in s and " date" not in s:
        s = s.replace("from datetime import datetime",
                      "from datetime import datetime, date")
    # añadir clases si faltan
    block = """
class LikeLog(db.Model):
    __tablename__ = "like_log"
    id = db.Column(db.Integer, primary_key=True)
    note_id = db.Column(db.Integer, db.ForeignKey("notes.id", ondelete="CASCADE"), nullable=False, index=True)
    fingerprint = db.Column(db.String(128), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)
    __table_args__ = (db.UniqueConstraint("note_id", "fingerprint", name="uq_like_note_fp"),)

class ViewLog(db.Model):
    __tablename__ = "view_log"
    id = db.Column(db.Integer, primary_key=True)
    note_id = db.Column(db.Integer, db.ForeignKey("notes.id", ondelete="CASCADE"), nullable=False, index=True)
    fingerprint = db.Column(db.String(128), nullable=False, index=True)
    view_date = db.Column(db.Date, nullable=False, index=True)  # 1 vista/día/persona
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False, index=True)
    __table_args__ = (db.UniqueConstraint("note_id", "fingerprint", "view_date", name="uq_view_note_fp_day"),)
"""
    # pegamos al final
    if not s.endswith("\n"): s += "\n"
    s += block
    p.write_text(s, encoding="utf-8")
    print("models.py: agregados LikeLog y ViewLog")
else:
    print("models.py: LikeLog y ViewLog ya presentes")
PY

############################################
# 2) RUTAS: like/view con unicidad por fingerprint
############################################
python - <<'PY'
from pathlib import Path, re
p = Path("backend/routes.py")
s = p.read_text(encoding="utf-8")

# imports requeridos
if "from hashlib import sha256" not in s:
    s = s.replace("from flask import Blueprint, request, jsonify",
                  "from flask import Blueprint, request, jsonify\nfrom hashlib import sha256")

if "from backend.models import Note, ReportLog" in s and "LikeLog" not in s:
    s = s.replace("from backend.models import Note, ReportLog",
                  "from backend.models import Note, ReportLog, LikeLog, ViewLog")
elif "from backend.models import Note" in s and "LikeLog" not in s:
    s = s.replace("from backend.models import Note",
                  "from backend.models import Note, LikeLog, ViewLog")

# helper fingerprint si falta
if "_fingerprint_from_request" not in s:
    ins = """
def _fingerprint_from_request(req):
    ip = (req.headers.get("X-Forwarded-For") or getattr(req, "remote_addr", "") or "").split(",")[0].strip()
    ua = req.headers.get("User-Agent", "")
    return sha256(f"{ip}|{ua}".encode("utf-8")).hexdigest()
"""
    s = s.replace("api = Blueprint(", ins + "\napi = Blueprint(")

# like_note idempotente
pat_like = r"@api\.route\(\"/notes/<int:note_id>/like\", methods=\[\"POST\"\]\)[\s\S]*?def\s+like_note\([^\)]*\):[\s\S]*?(?=\n@|\Z)"
new_like = """@api.route("/notes/<int:note_id>/like", methods=["POST"])
def like_note(note_id: int):
    n = db.session.get(Note, note_id)
    if not n:
        return jsonify({"error": "not_found"}), 404
    fp = _fingerprint_from_request(request)
    already = db.session.query(LikeLog.id).filter_by(note_id=note_id, fingerprint=fp).first()
    if already:
        return jsonify({"ok": True, "likes": n.likes or 0, "already_liked": True}), 200
    try:
        db.session.add(LikeLog(note_id=note_id, fingerprint=fp))
        n.likes = (n.likes or 0) + 1
        db.session.commit()
        return jsonify({"ok": True, "likes": n.likes}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": "like_failed", "detail": str(e)}), 500
"""

if re.search(pat_like, s, flags=re.S):
    s = re.sub(pat_like, new_like, s, flags=re.S)
else:
    s += "\n\n" + new_like

# view_note idempotente
pat_view = r"@api\.route\(\"/notes/<int:note_id>/view\", methods=\[\"POST\"\]\)[\s\S]*?def\s+view_note\([^\)]*\):[\s\S]*?(?=\n@|\Z)"
new_view = """@api.route("/notes/<int:note_id>/view", methods=["POST"])
def view_note(note_id: int):
    n = db.session.get(Note, note_id)
    if not n:
        return jsonify({"error": "not_found"}), 404
    fp = _fingerprint_from_request(request)
    today = datetime.utcnow().date()
    already = db.session.query(ViewLog.id).filter_by(note_id=note_id, fingerprint=fp, view_date=today).first()
    if already:
        return jsonify({"ok": True, "views": n.views or 0, "already_viewed": True}), 200
    try:
        db.session.add(ViewLog(note_id=note_id, fingerprint=fp, view_date=today))
        n.views = (n.views or 0) + 1
        db.session.commit()
        return jsonify({"ok": True, "views": n.views}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": "view_failed", "detail": str(e)}), 500
"""

if re.search(pat_view, s, flags=re.S):
    s = re.sub(pat_view, new_view, s, flags=re.S)
else:
    s += "\n\n" + new_view

Path("backend/routes.py").write_text(s, encoding="utf-8")
print("routes.py: like/view idempotentes con logs únicos")
PY

############################################
# 3) FRONTEND: marcar vista 1x/día y bloquear like localmente
############################################
cat > frontend/js/app.js <<'JS'
(function(){
  const $status = document.getElementById('status') || { textContent: '' };
  const $list   = document.getElementById('notes');
  const $form   = document.getElementById('noteForm');

  function fmtISO(s){ try{ return new Date(s).toLocaleString(); }catch(_){ return s||''; } }
  function toast(msg){
    let t = document.getElementById('toast');
    if(!t){
      t = document.createElement('div');
      t.id='toast';
      t.style.cssText='position:fixed;left:50%;bottom:18px;transform:translateX(-50%);background:#111a;color:#eaf2ff;padding:10px 14px;border-radius:10px;border:1px solid #253044;z-index:9999;transition:opacity .25s ease';
      document.body.appendChild(t);
    }
    t.textContent = msg; t.style.opacity='1'; setTimeout(()=>t.style.opacity='0', 1500);
  }
  function noteLink(id){ try{return location.origin+'/?note='+id;}catch(_){return '/?note='+id;} }

  async function apiLike(id){
    const r = await fetch(`/api/notes/${id}/like`, { method:'POST' });
    return r.json();
  }
  async function apiView(id){
    const r = await fetch(`/api/notes/${id}/view`, { method:'POST' });
    return r.json();
  }

  function renderNote(n){
    const li = document.createElement('li');
    li.className = 'note';
    li.id = 'note-'+n.id;
    li.dataset.id = n.id;

    const row = document.createElement('div');
    row.className = 'row';

    const txt = document.createElement('div');
    txt.className = 'txt';
    txt.textContent = String(n.text ?? '');

    const more = document.createElement('button');
    more.className = 'more';
    more.setAttribute('aria-label','Más opciones');
    more.textContent = '⋯';

    const menu = document.createElement('div');
    menu.className = 'menu';
    const btnReport = document.createElement('button');
    btnReport.textContent = 'Reportar';
    btnReport.addEventListener('click', async (ev)=>{
      ev.stopPropagation(); menu.classList.remove('open');
      try{
        const res = await fetch(`/api/notes/${n.id}/report`, {method:'POST'});
        const data = await res.json();
        if (data.deleted){ li.remove(); toast('Nota eliminada por reportes (5/5)'); }
        else if (data.already_reported){ toast('Ya reportaste'); }
        else if (data.ok){ toast(`Reporte (${data.reports||0}/5)`); }
      }catch(_){ toast('No se pudo reportar'); }
    });
    const btnShare = document.createElement('button');
    btnShare.textContent = 'Compartir';
    btnShare.addEventListener('click', async (ev)=>{
      ev.stopPropagation(); menu.classList.remove('open');
      const url = noteLink(n.id);
      if (navigator.share){ try{ await navigator.share({title:'Nota #'+n.id, url}); return; }catch(_){ } }
      try{ await navigator.clipboard.writeText(url); toast('Enlace copiado'); }
      catch(_){ window.prompt('Copia este enlace:', url); }
    });
    menu.appendChild(btnReport);
    menu.appendChild(btnShare);

    more.addEventListener('click', (ev)=>{ ev.stopPropagation(); menu.classList.toggle('open'); });

    row.appendChild(txt); row.appendChild(more); row.appendChild(menu);

    // barra de acciones
    const bar = document.createElement('div');
    bar.className = 'bar';

    const likeBtn = document.createElement('button');
    likeBtn.className = 'btn-like';
    likeBtn.innerHTML = '♥ Like <span class="like-count">'+(n.likes||0)+'</span>';
    likeBtn.addEventListener('click', async ()=>{
      if (likeBtn.dataset.locked==='1') return; // bloqueo local
      likeBtn.dataset.locked='1';
      try{
        const data = await apiLike(n.id);
        if (data.already_liked){ toast('Ya te gusta'); }
        if (typeof data.likes === 'number'){
          likeBtn.querySelector('.like-count').textContent = data.likes;
        }
      }catch(_){ likeBtn.dataset.locked='0'; toast('Error al dar like'); }
    });

    const views = document.createElement('span');
    views.className = 'views';
    views.innerHTML = '👁 <span class="view-count">'+(n.views||0)+'</span>';

    bar.appendChild(likeBtn);
    bar.appendChild(views);

    const meta = document.createElement('div');
    meta.className = 'meta';
    meta.textContent = `id #${n.id} · ${fmtISO(n.timestamp)} · expira: ${fmtISO(n.expires_at)}`;

    li.appendChild(row);
    li.appendChild(bar);
    li.appendChild(meta);

    // Observador de vistas (una vez)
    if ('IntersectionObserver' in window){
      const io = new IntersectionObserver(async entries=>{
        for (const e of entries){
          if (e.isIntersecting && !li.dataset.viewed){
            li.dataset.viewed='1';
            try{
              const data = await apiView(n.id);
              if (typeof data.views === 'number'){
                const vc = li.querySelector('.view-count');
                if (vc) vc.textContent = data.views;
              }
            }catch(_){}
            io.disconnect();
          }
        }
      }, {threshold: 0.5});
      io.observe(li);
    }else{
      // Fallback: marcar vista al crear
      apiView(n.id).then(data=>{
        if (typeof data.views === 'number'){
          const vc = li.querySelector('.view-count');
          if (vc) vc.textContent = data.views;
        }
      }).catch(()=>{});
    }

    return li;
  }

  async function fetchNotes(){
    $status.textContent = 'cargando…';
    try{
      const res = await fetch('/api/notes?page=1');
      const data = await res.json();
      $list.innerHTML = '';
      data.forEach(n => $list.appendChild(renderNote(n)));
      $status.textContent = 'ok';
    }catch(e){
      console.error(e);
      $status.textContent = 'error cargando';
    }
  }

  if ($form){
    $form.addEventListener('submit', async (ev)=>{
      ev.preventDefault();
      const fd = new FormData($form);
      try{
        const r = await fetch('/api/notes', { method:'POST', body: fd });
        if (!r.ok) throw new Error('HTTP '+r.status);
        await fetchNotes();
        $form.reset();
        const h = document.getElementById('hours'); if (h) h.value = 24;
      }catch(e){ alert('No se pudo publicar: '+e.message); }
    });
  }

  // cierra menús al click fuera
  document.addEventListener('click', ()=> {
    document.querySelectorAll('.note .menu.open').forEach(el => el.classList.remove('open'));
  });

  // scroll a ?note=ID
  try{
    const id = new URLSearchParams(location.search).get('note');
    if (id){
      setTimeout(()=>{ const el = document.getElementById('note-'+id); if (el) el.scrollIntoView({behavior:'smooth', block:'center'}); }, 150);
    }
  }catch(_){}

  fetchNotes();
})();
JS
echo "frontend/js/app.js actualizado"

############################################
# 4) Reinicio local + create_all (por si faltan tablas)
############################################
python - <<'PY'
from backend import create_app
from backend.models import db
app = create_app()
with app.app_context():
    db.create_all()
print("create_all() OK")
PY

pkill -f "python .*run\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "flask" 2>/dev/null || true
sleep 1
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
LOG="${PREFIX}/tmp/paste12_server.log"
mkdir -p "$(dirname "$LOG")"
nohup python - <<'PY' >"$LOG" 2>&1 & disown || true
from backend import create_app
app = create_app()
app.run(host="0.0.0.0", port=8000)
PY
sleep 2

echo "→ Smokes:"
echo -n "health="; curl -sS -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8000/api/health || true
# crear nota de prueba
curl -sS -H "Content-Type: application/json" -d '{"text":"prueba like/view","hours":24}' http://127.0.0.1:8000/api/notes >/dev/null
# tomar última
LID=$(curl -sS http://127.0.0.1:8000/api/notes | python - <<'PY'
import sys,json; d=json.load(sys.stdin); print(d[0]["id"])
PY
)
echo "last_id=$LID"
echo -n "like1="; curl -sS -o /dev/null -w "%{http_code}\n" -X POST "http://127.0.0.1:8000/api/notes/$LID/like"
echo -n "like2="; curl -sS -o /dev/null -w "%{http_code}\n" -X POST "http://127.0.0.1:8000/api/notes/$LID/like"
echo -n "view1="; curl -sS -o /dev/null -w "%{http_code}\n" -X POST "http://127.0.0.1:8000/api/notes/$LID/view"
echo -n "view2="; curl -sS -o /dev/null -w "%{http_code}\n" -X POST "http://127.0.0.1:8000/api/notes/$LID/view"

############################################
# 5) Commit
############################################
git add backend/models.py backend/routes.py frontend/js/app.js
git commit -m "feat(notes): like único por persona (LikeLog) y vista 1x/día por persona (ViewLog); frontend registra vistas y bloquea like local" || true
echo "✓ Listo. Sube con: git push origin main"
