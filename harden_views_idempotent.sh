#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
cd "$(dirname "$0")"
ts=$(date +%s)

echo "🔧 Harden views: 1 vista por usuario/día (backend) + dedupe 12h (frontend)"

# ---- Backups mínimos
cp -p backend/models.py "backend/models.py.bak.$ts" 2>/dev/null || true
cp -p backend/routes.py "backend/routes.py.bak.$ts" 2>/dev/null || true
cp -p frontend/index.html "frontend/index.html.bak.$ts" 2>/dev/null || true

# ---- 1) MODELS: agregar ViewLog si no existe
python - <<'PY'
from pathlib import Path
p = Path("backend/models.py")
code = p.read_text(encoding="utf-8")

if "class ViewLog" not in code:
    block = """

class ViewLog(db.Model):
    __tablename__ = "view_log"
    id = db.Column(db.Integer, primary_key=True)
    note_id = db.Column(db.Integer, db.ForeignKey('note.id', ondelete='CASCADE'), nullable=False, index=True)
    fingerprint = db.Column(db.String(128), nullable=False)
    day = db.Column(db.Date, nullable=False, index=True)
    created_at = db.Column(db.DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    __table_args__ = (db.UniqueConstraint('note_id','fingerprint','day', name='uq_view_note_fp_day'),)
"""
    # intentar pegarlo después de ReportLog si existe; sino al final
    if "class ReportLog" in code:
        idx = code.rfind("class ReportLog")
        # buscar fin del bloque ReportLog
        end = code.find("\nclass ", idx+1)
        if end == -1:
            end = len(code)
        code = code[:end] + block + code[end:]
    else:
        code = code.rstrip() + block
    p.write_text(code, encoding="utf-8")
    print("✓ ViewLog agregado a backend/models.py")
else:
    print("• ViewLog ya presente (ok)")
PY

# ---- 2) ROUTES: deduplicar /view (1 vez por usuario/día)
python - <<'PY'
from pathlib import Path, re
p = Path("backend/routes.py")
code = p.read_text(encoding="utf-8")

# asegurar import de ViewLog y utilidades
if "from .models import" in code and "ViewLog" not in code:
    code = re.sub(r"(from\s+\.\s*models\s+import\s+[^\n]+)",
                  lambda m: (m.group(1).rstrip() + ", ViewLog"),
                  code, count=1)

if "from flask import" in code and "request" not in code:
    code = code.replace("from flask import jsonify", "from flask import jsonify, request")
    code = code.replace("from flask import Blueprint, jsonify", "from flask import Blueprint, jsonify, request")

# localizar handler de /view
pat = re.compile(r'@bp\.post\("/notes/<int:note_id>/view"\)\s*def\s+view_note\([^)]*\):\s*([\s\S]*?)(?=\n\s*@|\Z)', re.M)
m = pat.search(code)
if not m:
    raise SystemExit("❌ No encontré la ruta POST /notes/<int:note_id>/view en backend/routes.py")

new_body = '''
@bp.post("/notes/<int:note_id>/view")
def view_note(note_id: int):
    """Cuenta la vista solo 1 vez por día por usuario (según fingerprint/cookie/ip)."""
    now = datetime.now(timezone.utc)
    n = Note.query.get_or_404(note_id)

    fp = request.headers.get("X-Client-Fingerprint") or request.cookies.get("p12_fp") or request.remote_addr or "anon"
    day = now.date()

    already = ViewLog.query.filter_by(note_id=note_id, fingerprint=fp, day=day).first()
    if already:
        return jsonify({"views": int(n.views or 0), "already_viewed": True})

    try:
        db.session.add(ViewLog(note_id=note_id, fingerprint=fp, day=day, created_at=now))
        n.views = (n.views or 0) + 1
        db.session.commit()
        return jsonify({"views": int(n.views or 0), "already_viewed": False})
    except Exception:
        db.session.rollback()
        # En caso de carrera, devolvemos el contador actual
        return jsonify({"views": int(n.views or 0), "already_viewed": True})
'''.lstrip("\n")

code = code[:m.start()] + new_body + code[m.end():]

# Añadir rate limit suave si no está ya decorado
if '@limiter.limit("120 per minute"' not in code and "@limiter.limit('120 per minute'" not in code:
    code = code.replace('@bp.post("/notes/<int:note_id>/view")',
                        '@limiter.limit("120 per minute")\n@bp.post("/notes/<int:note_id>/view")')

p.write_text(code, encoding="utf-8")
print("✓ /view ahora es idempotente (1 por día) y con rate limit.")
PY

# ---- 3) FRONTEND: crear views_counter.js si falta + incluirlo en index.html
mkdir -p frontend/js
if [ ! -f frontend/js/views_counter.js ]; then
cat > frontend/js/views_counter.js <<'JS'
// Dedup vistas por 12h en cliente + IntersectionObserver
(function(){
  const TTL_MS = 12 * 60 * 60 * 1000; // 12 horas
  const SEEN_KEY = (id)=>`p12_seen_${id}`;
  const now = Date.now();

  function seenRecently(id){
    try{
      const v = JSON.parse(localStorage.getItem(SEEN_KEY(id))||"null");
      return v && (now - v.ts) < TTL_MS;
    }catch(e){ return false; }
  }
  function markSeen(id){
    try{ localStorage.setItem(SEEN_KEY(id), JSON.stringify({ts:Date.now()})); }catch(e){}
  }

  async function postView(id){
    try{
      await fetch(`/api/notes/${id}/view`, {method:'POST'});
    }catch(e){}
  }

  const io = new IntersectionObserver((entries)=>{
    for(const it of entries){
      if(!it.isIntersecting) continue;
      const el = it.target;
      const id = el.getAttribute('data-id');
      if(!id || seenRecently(id)) continue;
      markSeen(id);
      postView(id);
    }
  }, {root:null, threshold:0.6});

  // auto-enganchar tarjetas
  function hook(){
    document.querySelectorAll('[data-note-id], .note-card').forEach(el=>{
      const id = el.getAttribute('data-note-id') || el.dataset.id;
      if(!id) return;
      if(!el._p12_io){
        el._p12_io = true;
        io.observe(el);
      }
    });
  }

  // primer hook y sobre DOM dinamico
  const mo = new MutationObserver(hook);
  mo.observe(document.documentElement, {childList:true, subtree:true});
  hook();
})();
JS
  echo "✓ creado frontend/js/views_counter.js"
else
  echo "• frontend/js/views_counter.js ya existe (ok)"
fi

# Incluirlo una sola vez en index.html
if ! grep -q 'views_counter.js' frontend/index.html; then
  perl -0777 -pe "s#</body>#  <script defer src=\"/js/views_counter.js?v=$ts\"></script>\n</body>#i" -i frontend/index.html
  echo "✓ index.html actualizado (incluye views_counter.js)"
else
  echo "• index.html ya incluye views_counter.js (ok)"
fi

# ---- 4) Validaciones de sintaxis
python -m py_compile backend/models.py
python -m py_compile backend/routes.py

# ---- 5) Migración mínima: crear tabla si falta
python - <<'PY'
import os, sys
sys.path.insert(0, os.getcwd())
from backend import create_app, db
from sqlalchemy import text
app = create_app()
with app.app_context():
    db.create_all()
    # ping rápido
    try:
        with db.engine.begin() as conn:
            conn.execute(text('SELECT 1'))
    except Exception as e:
        print("⚠️  Aviso DB:", e)
print("✓ migrate_min ok")
PY

# ---- 6) Commit + push → Render redeploy
git add backend/models.py backend/routes.py frontend/index.html frontend/js/views_counter.js
git commit -m "feat(views): idempotente 1 por usuario/día (ViewLog)+dedupe 12h en frontend + RL 120/min" || true
git push -u origin "$(git rev-parse --abbrev-ref HEAD)"

echo "🚀 Enviado. Abre tu sitio con cache-bust: /?v=$ts y mira en Network:"
echo "   - GET /api/notes → 200"
echo "   - Al scrollear: una única llamada POST /api/notes/{id}/view por tarjeta"
