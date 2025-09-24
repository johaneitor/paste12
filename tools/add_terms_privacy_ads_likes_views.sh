#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(pwd)"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
LOG="$PREFIX/tmp/paste12_server.log"
mkdir -p "$(dirname "$LOG")" "$ROOT/data"

backup(){ [ -f "$1" ] && cp -f "$1" "$1.bak.$(date +%s)" || true; }

echo "➤ Backups"
backup backend/models.py
backup backend/routes.py
backup backend/__init__.py
backup frontend/index.html
backup frontend/js/app.js
backup frontend/css/styles.css
backup public/index.html
backup public/js/app.js
backup public/css/styles.css
backup ads.txt

# ---------- helper: detectar carpeta estática ----------
choose_static_dir() {
  for d in frontend public static dist build; do
    if [ -d "$d" ]; then echo "$d"; return; fi
  done
  echo "public"
}
STATIC_DIR="$(choose_static_dir)"
mkdir -p "$STATIC_DIR/js" "$STATIC_DIR/css"

# ---------- MODELOS: asegurar ViewLog (vista única por día y fingerprint) ----------
echo "➤ Patch backend/models.py (Note, ReportLog, ViewLog)"
python - <<'PY'
from pathlib import Path
import re

p = Path("backend/models.py")
s = p.read_text(encoding="utf-8")

# Asegurar imports mínimos
if "from datetime import datetime" not in s:
    s = "from datetime import datetime\n" + s
if "from backend import db" not in s:
    s = "from backend import db\n" + s
if "from __future__ import annotations" not in s.splitlines()[0]:
    s = "from __future__ import annotations\n" + s

# Asegurar clase Note (no la reescribimos completa si ya está)
assert "class Note(" in s, "No encuentro Note en backend/models.py"

# Asegurar ReportLog (si no existe, lo añadimos)
if "class ReportLog(" not in s:
    s += """

class ReportLog(db.Model):
    __tablename__ = "report_log"
    id = db.Column(db.Integer, primary_key=True)
    note_id = db.Column(db.Integer, db.ForeignKey("notes.id", ondelete="CASCADE"), nullable=False, index=True)
    fingerprint = db.Column(db.String(128), nullable=False, index=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)
    __table_args__ = (db.UniqueConstraint("note_id", "fingerprint", name="uq_report_note_fp"),)
"""
# Asegurar ViewLog (única por nota+fp+fecha)
if "class ViewLog(" not in s:
    s += """

class ViewLog(db.Model):
    __tablename__ = "view_log"
    id = db.Column(db.Integer, primary_key=True)
    note_id = db.Column(db.Integer, db.ForeignKey("notes.id", ondelete="CASCADE"), nullable=False, index=True)
    fingerprint = db.Column(db.String(128), nullable=False, index=True)
    view_date = db.Column(db.Date, nullable=False, index=True)  # 1 vista/día/nota/fp
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False, index=True)
    __table_args__ = (db.UniqueConstraint("note_id", "fingerprint", "view_date", name="uq_view_note_fp_day"),)
"""
p.write_text(s, encoding="utf-8")
print("models.py actualizado")
PY

# ---------- RUTAS: vistas únicas/día, likes, get_note, health, list/create ----------
echo "➤ Patch backend/routes.py (endpoints completos)"
cat > backend/routes.py <<'PY'
from __future__ import annotations
from flask import Blueprint, request, jsonify, send_from_directory
from hashlib import sha256
from datetime import datetime, timedelta, date
from pathlib import Path

from backend import db
from backend.models import Note, ReportLog, ViewLog

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
        request.values.get("text"),
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

@api.route("/notes/<int:note_id>", methods=["GET"])
def get_note(note_id: int):
    n = db.session.get(Note, note_id)
    if not n:
        return jsonify({"error": "not_found"}), 404
    return jsonify(_to_dict(n)), 200

@api.route("/notes/<int:note_id>/like", methods=["POST"])
def like_note(note_id: int):
    n = db.session.get(Note, note_id)
    if not n:
        return jsonify({"error": "not_found"}), 404
    n.likes = (n.likes or 0) + 1
    db.session.commit()
    return jsonify({"ok": True, "likes": n.likes}), 200

@api.route("/notes/<int:note_id>/view", methods=["POST"])
def view_note(note_id: int):
    n = db.session.get(Note, note_id)
    if not n:
        return jsonify({"error": "not_found"}), 404
    fp = _fingerprint_from_request(request)
    today = date.today()
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
        db.session.add(ReportLog(note_id=note_id, fingerprint=fp))
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
PY

# ---------- BACKEND: opcional, servir /ads.txt si tu app no lo sirve ya ----------
# (no tocamos si ya lo tenés resuelto; solo creamos archivo ads.txt)
echo "➤ Escribiendo ads.txt (placeholder)"
cat > ads.txt <<'TXT'
# Reemplazá pub-XXXXXXXXXXXXXXXX con tu Publisher ID real de AdSense
google.com, pub-XXXXXXXXXXXXXXXX, DIRECT, f08c47fec0942fa0
TXT
# Copia también al estático por si se sirve desde ahí
cp -f ads.txt "$STATIC_DIR/ads.txt" 2>/dev/null || true

# ---------- FRONTEND: index con slot de anuncio + links T&C/Privacidad ----------
echo "➤ index.html (Términos, Privacidad y slot de anuncio)"
cat > "$STATIC_DIR/index.html" <<'HTML'
<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>paste12</title>
  <link rel="stylesheet" href="/css/styles.css">
  <!-- AdSense: reemplaza ca-pub-XXXXXXXXXXXXXXXX por tu ID real -->
  <script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=ca-pub-XXXXXXXXXXXXXXXX" crossorigin="anonymous"></script>
</head>
<body>
  <header class="topbar">
    <h1>Notas</h1>
    <nav class="links">
      <a href="/terms.html">Términos</a>
      <a href="/privacy.html">Privacidad</a>
    </nav>
  </header>

  <!-- Bloque de anuncio responsivo -->
  <section class="adwrap">
    <!-- Reemplaza data-ad-client y data-ad-slot con los tuyos -->
    <ins class="adsbygoogle"
         style="display:block"
         data-ad-client="ca-pub-XXXXXXXXXXXXXXXX"
         data-ad-slot="1234567890"
         data-ad-format="auto"
         data-full-width-responsive="true"></ins>
    <script>(adsbygoogle = window.adsbygoogle || []).push({});</script>
  </section>

  <main class="container">
    <form id="noteForm">
      <textarea name="text" placeholder="Escribe tu nota…" required></textarea>
      <input type="number" id="hours" name="hours" value="24" min="1" max="720">
      <button type="submit">Publicar</button>
      <span id="status"></span>
    </form>
    <ul id="notes"></ul>
  </main>

  <!-- Consentimiento simple -->
  <div id="consent" class="consent" hidden>
    Usamos cookies/localStorage (por ejemplo, para contar vistas y mostrar anuncios). Al continuar, aceptás nuestros
    <a href="/terms.html">Términos</a> y <a href="/privacy.html">Política de Privacidad</a>.
    <button id="consentAccept">Aceptar</button>
  </div>

  <script src="/js/app.js?v=4"></script>
  <script>
    // Banner de consentimiento muy simple
    (function(){
      try{
        if(!localStorage.getItem('consent')){
          var c=document.getElementById('consent');
          c.hidden=false;
          document.getElementById('consentAccept').onclick=function(){
            localStorage.setItem('consent','1'); c.hidden=true;
          };
        }
      }catch(e){}
    })();
  </script>
</body>
</html>
HTML

# ---------- FRONTEND: Terms & Privacy ----------
echo "➤ terms.html y privacy.html"
cat > "$STATIC_DIR/terms.html" <<'HTML'
<!doctype html>
<html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Términos y Condiciones</title><link rel="stylesheet" href="/css/styles.css"></head>
<body class="doc">
  <main class="container">
    <h1>Términos y Condiciones</h1>
    <p>Al usar este servicio aceptás estos términos. No publiques contenido ilegal, abusivo o que infrinja derechos de terceros.</p>
    <h2>Contenido de usuarios</h2>
    <p>El contenido publicado es responsabilidad de cada autor. Podremos remover notas que violen estos términos o hayan sido reportadas 5 veces por usuarios distintos.</p>
    <h2>Privacidad y datos</h2>
    <p>Podemos registrar información técnica (IP, agente de usuario) para prevención de abuso, conteo de vistas/likes/reportes y métricas de uso.</p>
    <h2>Limitación de responsabilidad</h2>
    <p>El servicio se ofrece “tal cual”. No garantizamos disponibilidad ni continuidad. Podremos cambiar o discontinuar el servicio en cualquier momento.</p>
    <p><a href="/">Volver</a></p>
  </main>
</body></html>
HTML

cat > "$STATIC_DIR/privacy.html" <<'HTML'
<!doctype html>
<html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Política de Privacidad</title><link rel="stylesheet" href="/css/styles.css"></head>
<body class="doc">
  <main class="container">
    <h1>Política de Privacidad</h1>
    <p>Recopilamos datos técnicos (IP, agente de usuario) para seguridad, anti-abuso y estadísticas (vistas/likes/reportes). Se usan cookies/localStorage para recordar preferencias y evitar conteos duplicados.</p>
    <h2>Publicidad</h2>
    <p>Podemos mostrar anuncios de terceros (p. ej., Google AdSense), que pueden usar cookies y/o identificadores para personalizar anuncios según sus políticas. Consultá las políticas del proveedor para más información.</p>
    <h2>Tus opciones</h2>
    <p>Podés usar bloqueadores de contenido y/o configurar tu navegador para limitar cookies. Si no aceptás nuestra política, por favor no uses el servicio.</p>
    <p><a href="/">Volver</a></p>
  </main>
</body></html>
HTML

# ---------- FRONTEND: app.js con likes+views visibles y view única por día ----------
echo "➤ app.js (likes, vistas, Observer, menú ⋯)"
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
        alert('No se pudo reportar: '+(data.detail||''));}
    }catch(e){ alert('Error de red al reportar'); }
  }

  async function likeNote(id, $likes){
    try{
      const res = await fetch('/api/notes/'+id+'/like', { method:'POST' });
      const data = await res.json();
      if(data.ok && typeof data.likes === 'number'){
        $likes.textContent = String(data.likes);
      }
    }catch(e){ console.error(e); }
  }

  async function viewNoteOncePerDay(id){
    try{
      const key = 'viewed_'+id+'_'+new Date().toISOString().slice(0,10);
      if(localStorage.getItem(key)) return;
      const res = await fetch('/api/notes/'+id+'/view', { method:'POST' });
      if(res.ok) localStorage.setItem(key,'1');
    }catch(e){}
  }

  function renderNote(n){
    const li = document.createElement('li'); li.className='note'; li.id='note-'+n.id;

    const row = document.createElement('div'); row.className='row';
    const txt = document.createElement('div'); txt.className='txt'; txt.textContent=String(n.text ?? '');

    const more = document.createElement('button'); more.className='more'; more.setAttribute('aria-label','Más opciones'); more.textContent='⋯';
    const menu = document.createElement('div'); menu.className='menu';

    const btnReport = document.createElement('button'); btnReport.textContent = 'Reportar';
    btnReport.addEventListener('click', ev=>{ ev.stopPropagation(); menu.classList.remove('open'); reportNote(n.id); });

    const btnShare = document.createElement('button'); btnShare.textContent = 'Compartir';
    btnShare.addEventListener('click', ev=>{
      ev.stopPropagation(); menu.classList.remove('open');
      const url = noteLink(n.id);
      if(navigator.share){ navigator.share({title:'Nota #'+n.id, url}).catch(()=>{}); return; }
      navigator.clipboard?.writeText(url).then(()=>toast('Enlace copiado')).catch(()=>{ prompt('Copia este enlace:', url); });
    });

    menu.appendChild(btnReport); menu.appendChild(btnShare);
    more.addEventListener('click', ev=>{ ev.stopPropagation(); menu.classList.toggle('open'); });

    const meta = document.createElement('div'); meta.className='meta';
    const spanId = document.createElement('span'); spanId.textContent = 'id #'+n.id;
    const sep1 = document.createElement('span'); sep1.textContent = ' · ';
    const spanTs = document.createElement('span'); spanTs.textContent = fmtISO(n.timestamp);
    const sep2 = document.createElement('span'); sep2.textContent = ' · expira: ';
    const spanExp = document.createElement('span'); spanExp.textContent = fmtISO(n.expires_at);

    // likes & views
    const bar = document.createElement('div'); bar.className='bar';
    const likeBtn = document.createElement('button'); likeBtn.className='like'; likeBtn.textContent='♥ Like';
    const likesCount = document.createElement('strong'); likesCount.className='likes'; likesCount.textContent=String(n.likes||0);
    const viewsIcon = document.createElement('span'); viewsIcon.textContent='· 👁 ';
    const viewsCount = document.createElement('strong'); viewsCount.className='views'; viewsCount.textContent=String(n.views||0);

    likeBtn.addEventListener('click', ()=>likeNote(n.id, likesCount));

    bar.appendChild(likeBtn);
    bar.appendChild(likesCount);
    bar.appendChild(viewsIcon);
    bar.appendChild(viewsCount);

    row.appendChild(txt); row.appendChild(more); row.appendChild(menu);
    li.appendChild(row);
    li.appendChild(meta);
    meta.appendChild(spanId); meta.appendChild(sep1); meta.appendChild(spanTs); meta.appendChild(sep2); meta.appendChild(spanExp);
    li.appendChild(bar);

    // observer para contar vista única por día
    const obs = new IntersectionObserver((entries)=>{
      entries.forEach(e=>{
        if(e.isIntersecting){
          viewNoteOncePerDay(n.id);
          obs.disconnect();
        }
      });
    }, { threshold: 0.3 });
    obs.observe(li);

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

# ---------- CSS ----------
echo "➤ styles.css (menú ⋯, barra likes/vistas, layout docs)"
cat >> "$STATIC_DIR/css/styles.css" <<'CSS'

/* layout básico */
body{margin:0;font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,'Helvetica Neue',Arial}
.container{max-width:860px;margin:20px auto;padding:0 16px}
.topbar{display:flex;justify-content:space-between;align-items:center;padding:10px 16px;border-bottom:1px solid #eee}
.topbar .links a{margin-left:12px;text-decoration:none;color:#3367d6}
.doc .container{max-width:760px}
.adwrap{max-width:860px;margin:12px auto}

/* notas */
#notes{list-style:none;padding:0;margin:16px 0}
.note{position:relative;border:1px solid #e9eef6;border-radius:12px;padding:12px 12px 8px;margin:10px 0;background:#fff}
.note .row{display:flex; gap:8px; align-items:flex-start; position:relative}
.note .row .txt{flex:1; white-space:pre-wrap}
.note .more{background:#1c2431;border:1px solid #273249;color:#dfeaff;border-radius:8px;cursor:pointer;padding:0 10px;height:28px}
.note .more + .menu{display:none;position:absolute;z-index:10;transform:translateY(30px);right:0;background:#0f141d;border:1px solid #273249;border-radius:10px;min-width:140px}
.note .more + .menu.open{display:block}
.note .more + .menu button{display:block;width:100%;text-align:left;padding:8px 10px;background:transparent;border:0;color:#eaf2ff;cursor:pointer}
.note .more + .menu button:hover{background:#141c28}
.note .meta{color:#57718e;font-size:12px;margin-top:6px}
.note .bar{display:flex;gap:8px;align-items:center;margin-top:8px}
.note .bar .like{background:#ffe5ea;border:1px solid #ffc2cf;border-radius:8px;padding:4px 10px;cursor:pointer}
.note .bar .likes, .note .bar .views{font-weight:700}

/* formulario */
#noteForm{display:grid;gap:8px;margin-top:8px}
#noteForm textarea{min-height:80px}

/* consent */
.consent{position:fixed;left:0;right:0;bottom:0;background:#0f141d;color:#eaf2ff;padding:10px 14px;border-top:1px solid #273249;display:flex;gap:10px;align-items:center;z-index:9998}
.consent a{color:#9fd1ff}
.consent button{margin-left:auto;background:#1c2431;border:1px solid #273249;color:#dfeaff;border-radius:8px;cursor:pointer;padding:6px 10px}
#toast{transition:opacity .25s ease}
CSS

# ---------- Reinicio local + create_all ----------
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
echo "notes_post=$(curl -sS -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -d '{\"text\":\"nota publicidad\",\"hours\":24}' http://127.0.0.1:8000/api/notes)"

# ---------- Commit & push ----------
echo "➤ Commit & push"
git add backend/models.py backend/routes.py "$STATIC_DIR/index.html" "$STATIC_DIR/js/app.js" "$STATIC_DIR/css/styles.css" ads.txt "$STATIC_DIR/terms.html" "$STATIC_DIR/privacy.html" "$STATIC_DIR/ads.txt" 2>/dev/null || true
git commit -m "feat(ads/policies/ui): Terms & Privacy; ads.txt; AdSense slot; likes+vistas en UI; vista única/día; menú ⋯ estable"
git push origin main || true

echo "✔ Listo. Recordatorio:"
echo "  1) Reemplazá ca-pub-XXXXXXXXXXXXXXXX y data-ad-slot en $STATIC_DIR/index.html."
echo "  2) Subí un ads.txt válido (ya hay placeholder en raiz y en $STATIC_DIR/ads.txt)."
echo "  3) Si en Render no ves el JS nuevo, hacé: Clear build cache & deploy."
echo "Log: $LOG  (tail -n 150 \"$LOG\")"
