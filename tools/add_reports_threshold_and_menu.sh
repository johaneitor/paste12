#!/usr/bin/env bash
set -Eeuo pipefail
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
LOG="$PREFIX/tmp/paste12_server.log"
mkdir -p "$(dirname "$LOG")"

echo "➤ Backups"
cp -f backend/models.py "backend/models.py.bak.$(date +%s)" 2>/dev/null || true
cp -f backend/routes.py "backend/routes.py.bak.$(date +%s)" 2>/dev/null || true

echo "➤ Patch models.py: agregar ReportLog (único por note_id+fingerprint)"
python - <<'PY'
from pathlib import Path, re
p = Path("backend/models.py")
s = p.read_text(encoding="utf-8")

# Si ya existe ReportLog, no hacer nada
if "class ReportLog(" in s:
    print("ReportLog ya existe.")
else:
    # Insertar ReportLog después de la clase Note
    s = re.sub(
        r"(class\s+Note\(db\.Model\):[\s\S]*?)(\nclass|\Z)",
        r"""\\1

class ReportLog(db.Model):
    __tablename__ = "report_log"
    id = db.Column(db.Integer, primary_key=True)
    note_id = db.Column(db.Integer, db.ForeignKey("notes.id", ondelete="CASCADE"), nullable=False, index=True)
    fingerprint = db.Column(db.String(128), nullable=False, index=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)
    __table_args__ = (db.UniqueConstraint("note_id", "fingerprint", name="uq_report_note_fp"),)

\\2""",
        s,
        flags=re.S
    )
    p.write_text(s, encoding="utf-8")
    print("models.py: ReportLog agregado.")
PY

echo "➤ Patch routes.py: fingerprint helper + GET /api/notes/<id> + report con umbral 5"
python - <<'PY'
from pathlib import Path, re
p = Path("backend/routes.py")
s = p.read_text(encoding="utf-8")

# Asegurar import de ReportLog y sha256
if "from hashlib import sha256" not in s:
    s = s.replace("from flask import Blueprint, request, jsonify",
                  "from flask import Blueprint, request, jsonify\nfrom hashlib import sha256")

if "ReportLog" not in s:
    s = s.replace("from backend.models import Note",
                  "from backend.models import Note, ReportLog")

# Helper fingerprint
if "_fingerprint_from_request" not in s:
    s = s.replace(
        "api = Blueprint(\"api\", __name__, url_prefix=\"/api\")",
        "api = Blueprint(\"api\", __name__, url_prefix=\"/api\")\n\n"
        "def _fingerprint_from_request(req):\n"
        "    ip = (req.headers.get('X-Forwarded-For') or getattr(req, 'remote_addr', '') or '').split(',')[0].strip()\n"
        "    ua = req.headers.get('User-Agent', '')\n"
        "    return sha256(f\"{ip}|{ua}\".encode('utf-8')).hexdigest()\n"
    )

# GET /api/notes/<id>
if '@api.route("/notes/<int:note_id>", methods=["GET"])' not in s:
    s += (
        "\n\n@api.route(\"/notes/<int:note_id>\", methods=[\"GET\"])"
        "\ndef get_note(note_id: int):\n"
        "    n = db.session.get(Note, note_id)\n"
        "    if not n:\n"
        "        return jsonify({\"error\": \"not_found\"}), 404\n"
        "    def _to_dict(n):\n"
        "        return {\n"
        "            \"id\": n.id,\n"
        "            \"text\": n.text,\n"
        "            \"timestamp\": n.timestamp.isoformat() if getattr(n, 'timestamp', None) else None,\n"
        "            \"expires_at\": n.expires_at.isoformat() if getattr(n, 'expires_at', None) else None,\n"
        "            \"likes\": getattr(n, 'likes', 0) or 0,\n"
        "            \"views\": getattr(n, 'views', 0) or 0,\n"
        "            \"reports\": getattr(n, 'reports', 0) or 0,\n"
        "        }\n"
        "    return jsonify(_to_dict(n)), 200\n"
    )

# Reescribir /report con lógica de único reporte y eliminación al llegar a 5
pat = r"@api\.route\(\"/notes/<int:note_id>/report\".*?def\s+report_note\(note_id:\s*int\):[\s\S]*?(?=\n@|\Z)"
new = '''
@api.route("/notes/<int:note_id>/report", methods=["POST"])
def report_note(note_id: int):
    n = db.session.get(Note, note_id)
    if not n:
        return jsonify({"error": "not_found"}), 404

    fp = _fingerprint_from_request(request)
    # ¿ya reportó?
    already = db.session.query(ReportLog.id).filter_by(note_id=note_id, fingerprint=fp).first()
    if already:
        # No incrementar; devolver estado actual
        return jsonify({"ok": True, "reports": n.reports or 0, "already_reported": True}), 200

    try:
        # Registrar log único y subir contador
        rl = ReportLog(note_id=note_id, fingerprint=fp)
        db.session.add(rl)
        n.reports = (n.reports or 0) + 1

        # Si llegó a 5, borrar la nota
        if n.reports >= 5:
            db.session.delete(n)  # FK con ondelete=CASCADE limpia report_log en PG
            db.session.commit()
            return jsonify({"ok": True, "deleted": True, "reports": 5}), 200

        db.session.commit()
        return jsonify({"ok": True, "reports": n.reports}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": "report_failed", "detail": str(e)}), 500
'''
s2, n = re.subn(pat, new, s, flags=re.S)
if n == 0 and 'def report_note(' not in s:
    # No había handler; lo agregamos
    s += new

p.write_text(s2 if n else s, encoding="utf-8")
print("routes.py: handler de report actualizado.")
PY

echo "➤ Frontend: menú ⋯ con Reportar y Compartir"
# Detectar carpeta estática (frontend/public/static/dist/build); si no existe, usar public/
choose_static_dir() {
  for d in frontend public static dist build; do
    if [ -d "$d" ]; then echo "$d"; return; fi
  done
  echo "public"
}
STATIC_DIR="$(choose_static_dir)"
mkdir -p "$STATIC_DIR/js" "$STATIC_DIR/css"

# Asegurar index.html, js y css existen al menos vacíos
[ -f "$STATIC_DIR/index.html" ] || echo "<!doctype html><title>paste12</title><ul id='notes'></ul><script src='/js/app.js?v=1'></script>" > "$STATIC_DIR/index.html"
[ -f "$STATIC_DIR/js/app.js" ] || echo "(function(){})();" > "$STATIC_DIR/js/app.js"
[ -f "$STATIC_DIR/css/styles.css" ] || echo "" > "$STATIC_DIR/css/styles.css"

# Parchear JS para incluir menú y acciones
python - <<'PY'
from pathlib import Path, re, json
root = Path(".")
# encontrar js/app.js en carpeta estática
for base in ["frontend", "public", "static", "dist", "build"]:
    p = root / base / "js" / "app.js"
    if p.exists():
        js = p.read_text(encoding="utf-8")
        break
else:
    p = root / "public" / "js" / "app.js"
    p.parent.mkdir(parents=True, exist_ok=True)
    js = ""

menu_helpers = """
function noteLink(id){
  try { return location.origin + "/?note=" + id; } catch { return "/?note="+id; }
}
async function reportNote(id){
  try{
    const res = await fetch(`/api/notes/${id}/report`, {method: 'POST'});
    const data = await res.json();
    if (data.deleted){
      const el = document.getElementById(`note-${id}`);
      if (el) el.remove();
      toast('Nota eliminada por reportes (5/5)');
    }else if (data.already_reported){
      toast('Ya reportaste esta nota');
    }else if (data.ok){
      toast(`Reporte registrado (${data.reports}/5)`);
    }else{
      alert('No se pudo reportar: ' + (data.detail||''));
    }
  }catch(e){ alert('Error de red al reportar'); }
}
async function shareNote(id){
  const url = noteLink(id);
  if (navigator.share){
    try{ await navigator.share({title:'Nota #' + id, url}); return; }catch(e){}
  }
  try{
    await navigator.clipboard.writeText(url);
    toast('Enlace copiado');
  }catch(e){
    prompt('Copia este enlace:', url);
  }
}
function toast(msg){
  let t = document.getElementById('toast');
  if (!t){
    t = document.createElement('div');
    t.id='toast';
    t.style.cssText='position:fixed;left:50%;bottom:18px;transform:translateX(-50%);background:#111a;color:#eaf2ff;padding:10px 14px;border-radius:10px;border:1px solid #253044;z-index:9999';
    document.body.appendChild(t);
  }
  t.textContent = msg;
  t.style.opacity='1';
  setTimeout(()=>{ t.style.opacity='0'; }, 1800);
}
"""

# Insertar helpers si no están
if "function reportNote(" not in js:
    js = menu_helpers + "\n" + js

# Inject render de item con menú ⋯ ; buscamos lugar donde se arma cada <li>
if "class=\"note\"" in js and "⋯" in js:
    pass  # ya parcheado
else:
    # Intentar reemplazar el render existente simple por uno con menú
    js = re.sub(
        r"li\.innerHTML\s*=\s*`[^`]*`;",
        r"""li.innerHTML = `
          <div class="row">
            <div class="txt">\${n.text ?? ''}</div>
            <button class="more" aria-label="Más opciones" onclick="this.nextElementSibling.classList.toggle('open')">⋯</button>
            <div class="menu">
              <button onclick="reportNote(\${n.id})">Reportar</button>
              <button onclick="shareNote(\${n.id})">Compartir</button>
            </div>
          </div>
          <div class="meta">
            <span>id #\${n.id}</span>
            <span> · </span>
            <span>\${fmtISO(n.timestamp)}</span>
            <span> · expira: \${fmtISO(n.expires_at)}</span>
          </div>`;""",
        js
    )

# Asegurar que cada <li> tenga id="note-<id>"
js = re.sub(r"const li = document\.createElement\('li'\);\s*li\.className = 'note';",
            "const li = document.createElement('li');\nli.className='note';\nli.id = `note-${n.id}`;", js)

# Al cargar, si viene ?note=ID, hacer scroll
if "scrollIntoView" not in js or "URLSearchParams" not in js:
    js += """
(function(){
  try{
    const params = new URLSearchParams(location.search);
    const h = params.get('note');
    if (h){
      const el = document.getElementById('note-' + h);
      if (el) el.scrollIntoView({behavior:'smooth', block:'center'});
    }
  }catch(e){}
})();
"""

p.write_text(js, encoding="utf-8")
print("app.js: menú ⋯ con Reportar/Compartir agregado.")
PY

# Unos estilos mínimos para el menú ⋯
STATIC_DIR_JS_CSS_FOUND=""
for d in frontend public static dist build; do
  if [ -f "$d/css/styles.css" ]; then STATIC_DIR_JS_CSS_FOUND="$d"; break; fi
done
[ -z "$STATIC_DIR_JS_CSS_FOUND" ] && STATIC_DIR_JS_CSS_FOUND="public"
cat >> "$STATIC_DIR_JS_CSS_FOUND/css/styles.css" <<'CSS'

/* menú ⋯ */
.note .row{display:flex; gap:8px; align-items:flex-start}
.note .row .txt{flex:1}
.note .more{background:#1c2431;border:1px solid #273249;color:#dfeaff;border-radius:8px;cursor:pointer;padding:0 10px;height:28px}
.note .menu{position:relative;display:inline-block}
.note .menu{position:relative}
.note .menu.open, .note .menu:has(button){display:inline-block}
.note .menu{display:none}
.note .more + .menu{display:none;position:absolute;z-index:10;transform:translateY(30px);right:0;background:#0f141d;border:1px solid #273249;border-radius:10px;min-width:140px}
.note .more + .menu.open{display:block}
.note .more + .menu button{display:block;width:100%;text-align:left;padding:8px 10px;background:transparent;border:0;color:#eaf2ff}
.note .more + .menu button:hover{background:#141c28}
#toast{transition:opacity .25s ease}
CSS

echo "➤ Reinicio local y create_all()"
pkill -f "python .*run\.py" 2>/dev/null || true
sleep 1
nohup python - <<'PY' >"$LOG" 2>&1 &
from run import app
with app.app_context():
    from backend.models import db
    db.create_all()
PY
sleep 1
nohup python run.py >>"$LOG" 2>&1 & disown || true
sleep 2

echo "health=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/api/health)"
echo "notes=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/api/notes)"
echo "report_smoke=$(curl -sS -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:8000/api/notes/1/report || true)"

echo "➤ Commit & push"
git add backend/models.py backend/routes.py "$STATIC_DIR/index.html" "$STATIC_DIR/js/app.js" "$STATIC_DIR_JS_CSS_FOUND/css/styles.css"
git commit -m "feat(reports): 1 reporte por persona; borrar nota al 5º reporte; menú ⋯ con Reportar/Compartir en UI"
git push origin main || true

echo "Log: $LOG  (tail -n 120 \"$LOG\")"
