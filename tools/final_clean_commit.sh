#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(pwd)"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
LOG="$PREFIX/tmp/paste12_server.log"
mkdir -p "$(dirname "$LOG")" "$ROOT/data"

backup() { [ -f "$1" ] && cp -f "$1" "$1.bak.$(date +%s)" || true; }

echo "➤ Backups"
backup backend/models.py
backup backend/routes.py
backup frontend/index.html
backup frontend/js/app.js
backup public/index.html
backup public/js/app.js

# ========== backend/models.py (estable, sin Index() explícito) ==========
echo "➤ Escribiendo backend/models.py (Note + ReportLog)"
cat > backend/models.py <<'PY'
from __future__ import annotations
from datetime import datetime
from backend import db

class Note(db.Model):
    __tablename__ = "notes"
    id         = db.Column(db.Integer, primary_key=True)
    text       = db.Column(db.Text, nullable=False)
    timestamp  = db.Column(db.DateTime, default=datetime.utcnow, nullable=False, index=True)
    expires_at = db.Column(db.DateTime, nullable=True, index=True)
    likes      = db.Column(db.Integer, default=0, nullable=False)
    views      = db.Column(db.Integer, default=0, nullable=False)
    reports    = db.Column(db.Integer, default=0, nullable=False)
    author_fp  = db.Column(db.String(128), index=True, nullable=True)

class ReportLog(db.Model):
    __tablename__ = "report_log"
    id = db.Column(db.Integer, primary_key=True)
    note_id = db.Column(db.Integer, db.ForeignKey("notes.id", ondelete="CASCADE"), nullable=False, index=True)
    fingerprint = db.Column(db.String(128), nullable=False, index=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)
    __table_args__ = (db.UniqueConstraint("note_id", "fingerprint", name="uq_report_note_fp"),)
PY

# ========== backend/routes.py (estable, con report threshold=5) ==========
echo "➤ Escribiendo backend/routes.py (health/list/create/like/view/report/get)"
cat > backend/routes.py <<'PY'
from __future__ import annotations
from flask import Blueprint, request, jsonify
from hashlib import sha256
from datetime import datetime, timedelta

from backend import db
from backend.models import Note, ReportLog

api = Blueprint("api", __name__, url_prefix="/api")

def _fingerprint_from_request(req):
    ip = (req.headers.get("X-Forwarded-For") or getattr(req, "remote_addr", "") or "").split(",")[0].strip()
    ua = req.headers.get("User-Agent", "")
    return sha256(f"{ip}|{ua}".encode("utf-8")).hexdigest()

def _to_dict(n: Note):
    return {
        "id": n.id,
        "text": n.text,
        "timestamp": n.timestamp.isoformat() if getattr(n, "timestamp", None) else None,
        "expires_at": n.expires_at.isoformat() if getattr(n, "expires_at", None) else None,
        "likes": getattr(n, "likes", 0) or 0,
        "views": getattr(n, "views", 0) or 0,
        "reports": getattr(n, "reports", 0) or 0,
    }

@api.route("/health", methods=["GET"])
def health():
    return jsonify({"ok": True}), 200

@api.route("/notes", methods=["GET"])
def list_notes():
    try:
        page = int((request.args.get("page") or "1").strip() or "1")
    except Exception:
        page = 1
    if page < 1:
        page = 1

    q = db.session.query(Note).order_by(Note.id.desc())
    items = q.limit(20).offset((page - 1) * 20).all()
    return jsonify([_to_dict(n) for n in items]), 200

@api.route("/notes", methods=["POST"])
def create_note():
    # Aceptar JSON, form-data, x-www-form-urlencoded y querystring
    raw_json = request.get_json(silent=True) or {}
    data = raw_json if isinstance(raw_json, dict) else {}

    def pick(*vals):
        for v in vals:
            if v is not None and str(v).strip() != "":
                return str(v)
        return ""

    text = pick(
        data.get("text") if isinstance(data, dict) else None,
        request.form.get("text"),
        request.values.get("text"),  # incluye querystring y form
    ).strip()

    hours_raw = pick(
        (data.get("hours") if isinstance(data, dict) else None),
        request.form.get("hours"),
        request.values.get("hours"),
        "24",
    )
    try:
        hours = int(hours_raw)
    except Exception:
        hours = 24

    if not text:
        return jsonify({"error": "text_required"}), 400

    hours = max(1, min(hours, 720))
    now = datetime.utcnow()
    try:
        n = Note(
            text=text,
            timestamp=now,
            expires_at=now + timedelta(hours=hours),
            author_fp=_fingerprint_from_request(request),
        )
        db.session.add(n)
        db.session.commit()
        return jsonify({"id": n.id, "ok": True}), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": "create_failed", "detail": str(e)}), 500

@api.route("/notes/<int:note_id>/view", methods=["POST"])
def view_note(note_id: int):
    n = db.session.get(Note, note_id)
    if not n:
        return jsonify({"error": "not_found"}), 404
    n.views = (n.views or 0) + 1
    db.session.commit()
    return jsonify({"ok": True, "views": n.views})

@api.route("/notes/<int:note_id>/like", methods=["POST"])
def like_note(note_id: int):
    n = db.session.get(Note, note_id)
    if not n:
        return jsonify({"error": "not_found"}), 404
    n.likes = (n.likes or 0) + 1
    db.session.commit()
    return jsonify({"ok": True, "likes": n.likes})

@api.route("/notes/<int:note_id>/report", methods=["POST"])
def report_note(note_id: int):
    n = db.session.get(Note, note_id)
    if not n:
        return jsonify({"error": "not_found"}), 404

    fp = _fingerprint_from_request(request)
    already = db.session.query(ReportLog.id).filter_by(note_id=note_id, fingerprint=fp).first()
    if already:
        return jsonify({"ok": True, "reports": n.reports or 0, "already_reported": True}), 200

    try:
        rl = ReportLog(note_id=note_id, fingerprint=fp)
        db.session.add(rl)
        n.reports = (n.reports or 0) + 1

        if n.reports >= 5:
            db.session.delete(n)
            db.session.commit()
            return jsonify({"ok": True, "deleted": True, "reports": 5}), 200

        db.session.commit()
        return jsonify({"ok": True, "reports": n.reports}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": "report_failed", "detail": str(e)}), 500

@api.route("/notes/<int:note_id>", methods=["GET"])
def get_note(note_id: int):
    n = db.session.get(Note, note_id)
    if not n:
        return jsonify({"error": "not_found"}), 404
    return jsonify(_to_dict(n)), 200
PY

# ========== FRONTEND estático ==========
choose_static_dir() {
  for d in frontend public static dist build; do
    if [ -d "$d" ]; then echo "$d"; return; fi
  done
  echo "public"
}
STATIC_DIR="$(choose_static_dir)"
mkdir -p "$STATIC_DIR/js" "$STATIC_DIR/css"

# index.html básico (si no existe) o solo ajustar el <script> a v=3
if [ ! -f "$STATIC_DIR/index.html" ]; then
  echo "➤ Creando $STATIC_DIR/index.html mínimo"
  cat > "$STATIC_DIR/index.html" <<'HTML'
<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>paste12</title>
  <link rel="stylesheet" href="/css/styles.css">
</head>
<body>
  <main class="container">
    <h1>Notas</h1>
    <form id="noteForm">
      <textarea name="text" placeholder="Escribe tu nota…" required></textarea>
      <input type="number" id="hours" name="hours" value="24" min="1" max="720">
      <button type="submit">Publicar</button>
      <span id="status"></span>
    </form>
    <ul id="notes"></ul>
  </main>
  <script src="/js/app.js?v=3"></script>
</body>
</html>
HTML
else
  echo "➤ Ajustando versión de JS en $STATIC_DIR/index.html (v=3)"
  sed -i -E 's#/js/app\.js(\?v=[^"]*)?"#/js/app.js?v=3"#g' "$STATIC_DIR/index.html" || true
fi

# app.js: versión DOM limpia (sin literales ${...})
echo "➤ Escribiendo $STATIC_DIR/js/app.js (renderer DOM + menú ⋯)"
cat > "$STATIC_DIR/js/app.js" <<'JS'
(function(){
  const $status = document.getElementById('status') || (()=>{const s=document.createElement('span');s.id='status';document.body.appendChild(s);return s;})();
  const $list = document.getElementById('notes') || (()=>{const u=document.createElement('ul');u.id='notes';document.body.appendChild(u);return u;})();
  const $form = document.getElementById('noteForm');

  function fmtISO(s){ try{ return new Date(s).toLocaleString(); }catch(_){ return s||''; } }
  function toast(msg){
    let t = document.getElementById('toast');
    if(!t){
      t = document.createElement('div');
      t.id='toast';
      t.style.cssText='position:fixed;left:50%;bottom:18px;transform:translateX(-50%);background:#111a;color:#eaf2ff;padding:10px 14px;border-radius:10px;border:1px solid #253044;z-index:9999;transition:opacity .25s ease';
      document.body.appendChild(t);
    }
    t.textContent = msg; t.style.opacity='1';
    setTimeout(()=>{ t.style.opacity='0'; }, 1800);
  }
  function noteLink(id){ try{ return location.origin + '/?note=' + id; }catch(_){ return '/?note='+id; } }
  async function reportNote(id){
    try{
      const res = await fetch('/api/notes/'+id+'/report', { method: 'POST' });
      const data = await res.json();
      if(data.deleted){
        const el = document.getElementById('note-'+id); if(el) el.remove();
        toast('Nota eliminada por reportes (5/5)');
      }else if(data.already_reported){
        toast('Ya reportaste esta nota');
      }else if(data.ok){
        toast('Reporte registrado ('+(data.reports||0)+'/5)');
      }else{
        alert('No se pudo reportar: '+(data.detail||'')); }
    }catch(e){ alert('Error de red al reportar'); }
  }
  async function shareNote(id){
    const url = noteLink(id);
    if(navigator.share){ try{ await navigator.share({ title: 'Nota #'+id, url }); return; }catch(_){ } }
    try{ await navigator.clipboard.writeText(url); toast('Enlace copiado'); }
    catch(_){ window.prompt('Copia este enlace', url); }
  }
  function renderNote(n){
    const li = document.createElement('li'); li.className='note'; li.id='note-'+n.id;
    const row = document.createElement('div'); row.className='row';
    const txt = document.createElement('div'); txt.className='txt'; txt.textContent=String(n.text ?? '');
    const more = document.createElement('button'); more.className='more'; more.setAttribute('aria-label','Más opciones'); more.textContent='⋯';
    const menu = document.createElement('div'); menu.className='menu';
    const btnReport = document.createElement('button'); btnReport.textContent='Reportar';
    btnReport.addEventListener('click', ev=>{ ev.stopPropagation(); menu.classList.remove('open'); reportNote(n.id); });
    const btnShare = document.createElement('button'); btnShare.textContent='Compartir';
    btnShare.addEventListener('click', ev=>{ ev.stopPropagation(); menu.classList.remove('open'); shareNote(n.id); });
    menu.appendChild(btnReport); menu.appendChild(btnShare);
    more.addEventListener('click', ev=>{ ev.stopPropagation(); menu.classList.toggle('open'); });
    row.appendChild(txt); row.appendChild(more); row.appendChild(menu);
    const meta = document.createElement('div'); meta.className='meta';
    meta.appendChild(document.createTextNode('id #'+n.id+' · '+fmtISO(n.timestamp)+' · expira: '+fmtISO(n.expires_at)));
    li.appendChild(row); li.appendChild(meta);
    return li;
  }
  async function fetchNotes(){
    $status.textContent='cargando…';
    try{
      const res = await fetch('/api/notes?page=1');
      const data = await res.json();
      $list.innerHTML=''; data.forEach(n=> $list.appendChild(renderNote(n)));
      $status.textContent='ok';
    }catch(e){ console.error(e); $status.textContent='error cargando'; }
  }
  // cerrar menús al clickear fuera
  document.addEventListener('click', ()=> {
    document.querySelectorAll('.note .menu.open').forEach(el => el.classList.remove('open'));
  });
  if($form){
    $form.addEventListener('submit', async ev=>{
      ev.preventDefault();
      const fd = new FormData($form);
      try{
        const res = await fetch('/api/notes', { method:'POST', body: fd });
        if(!res.ok) throw new Error('HTTP '+res.status);
        await fetchNotes(); $form.reset(); const h=document.getElementById('hours'); if(h) h.value=24;
      }catch(e){ alert('No se pudo publicar la nota: '+e.message); }
    });
  }
  // jump a ?note=ID
  try{
    const params = new URLSearchParams(location.search);
    const id = params.get('note');
    if(id){ setTimeout(()=>{ const el=document.getElementById('note-'+id); if(el) el.scrollIntoView({behavior:'smooth', block:'center'}); }, 150); }
  }catch(_){}
  fetchNotes();
})();
JS

# CSS: asegurar estilos del menú ⋯
CSS_FILE=""
for d in frontend public static dist build; do
  if [ -f "$d/css/styles.css" ]; then CSS_FILE="$d/css/styles.css"; break; fi
done
[ -z "$CSS_FILE" ] && CSS_FILE="$STATIC_DIR/css/styles.css"
mkdir -p "$(dirname "$CSS_FILE")"
grep -q ".note .more" "$CSS_FILE" 2>/dev/null || cat >> "$CSS_FILE" <<'CSS'
/* menú ⋯ */
.note .row{display:flex; gap:8px; align-items:flex-start; position:relative}
.note .row .txt{flex:1}
.note .more{background:#1c2431;border:1px solid #273249;color:#dfeaff;border-radius:8px;cursor:pointer;padding:0 10px;height:28px}
.note .more + .menu{display:none;position:absolute;z-index:10;transform:translateY(30px);right:0;background:#0f141d;border:1px solid #273249;border-radius:10px;min-width:140px}
.note .more + .menu.open{display:block}
.note .more + .menu button{display:block;width:100%;text-align:left;padding:8px 10px;background:transparent;border:0;color:#eaf2ff}
.note .more + .menu button:hover{background:#141c28}
#toast{transition:opacity .25s ease}
CSS

# ========== restart + smokes ==========
echo "➤ Reinicio local"
pkill -f "python .*run\.py" 2>/dev/null || true
sleep 1
nohup python - <<'PY' >"$LOG" 2>&1 &
from backend import create_app
app = create_app()
with app.app_context():
    from backend.models import db
    db.create_all()
PY
sleep 1
nohup python run.py >>"$LOG" 2>&1 & disown || true
sleep 2

echo "health=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/api/health)"
echo "notes_get=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/api/notes)"
echo "notes_post=$(curl -sS -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -d '{\"text\":\"nota clean\",\"hours\":24}' http://127.0.0.1:8000/api/notes)"

echo "➤ Commit & push"
git add backend/models.py backend/routes.py "$STATIC_DIR/index.html" "$STATIC_DIR/js/app.js" "$CSS_FILE"
git commit -m "fix(core/ui): normalizar modelos/rutas; ReportLog (1 por persona); borrar al 5º reporte; frontend DOM renderer; menú ⋯; bust cache v=3"
git push origin main || true

echo "✔ Listo. Si en Render no ves el JS nuevo, hacé: Clear build cache & deploy."
echo "Log: $LOG (tail -n 150 \"$LOG\")"
