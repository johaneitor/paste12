#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

ts=$(date +%s)
echo "🗂️  Backups con sufijo .$ts"

# 1) MODELO: agregar columnas likes y views
cp -p backend/models.py backend/models.py.bak.$ts
python - <<'PY'
from pathlib import Path
p=Path("backend/models.py"); s=p.read_text()
if "likes  = db.Column(db.Integer" not in s:
    s=s.replace("class Note(db.Model):\n",
"""class Note(db.Model):
    id          = db.Column(db.Integer, primary_key=True)
""")  # no hace nada, sólo asegura el replace siguiente
    s=s.replace(
"    reports     = db.Column(db.Integer, default=0)\n    user_token  = db.Column(db.String(64), index=True)\n",
"    reports     = db.Column(db.Integer, default=0)\n    user_token  = db.Column(db.String(64), index=True)\n    likes       = db.Column(db.Integer, default=0, nullable=False)\n    views       = db.Column(db.Integer, default=0, nullable=False)\n"
)
p.write_text(s)
print("✓ models.py: columnas likes/views")
PY

# 2) RUTAS: exponer contadores y endpoints /like y /view
cp -p backend/routes.py backend/routes.py.bak.$ts
python - <<'PY'
from pathlib import Path
import re, textwrap
p=Path("backend/routes.py"); s=p.read_text()

# Asegurar imports
if "from datetime import" in s and "timedelta" not in s:
    s=s.replace("from datetime import datetime, timezone", "from datetime import datetime, timezone, timedelta")
if "from flask_limiter" not in s:
    s = "from flask_limiter import Limiter\nfrom flask_limiter.util import get_remote_address\n" + s

# GET /notes debe incluir likes y views
s=re.sub(r"notes.append\(\{[^}]*\}\)",
          'notes.append({"id": n.id, "text": n.text, "likes": n.likes, "views": n.views})',
          s)

# Endpoint LIKE
if "@bp.post(\"/notes/<int:note_id>/like\")" not in s:
    s += textwrap.dedent("""
    @bp.post("/notes/<int:note_id>/like")
    def like_note(note_id):
        note = Note.query.get_or_404(note_id)
        note.likes = (note.likes or 0) + 1
        db.session.commit()
        return {"ok": True, "likes": note.likes}, 200
    """)

# Endpoint VIEW (impresión controlada)
if "@bp.post(\"/notes/<int:note_id>/view\")" not in s:
    s += textwrap.dedent("""
    @bp.post("/notes/<int:note_id>/view")
    def view_note(note_id):
        note = Note.query.get_or_404(note_id)
        note.views = (note.views or 0) + 1
        db.session.commit()
        return {"ok": True, "views": note.views}, 200
    """)

# Limitar abuso por IP y nota (requiere Flask-Limiter ya inicializado en create_app)
if "def require_token" in s:
    pass
# Añadimos reglas al final (simple y efectivo). En producción usar Redis.
if "## rate limits per endpoint" not in s:
    s += textwrap.dedent("""
    ## rate limits per endpoint
    try:
        from flask import current_app
        limiter = current_app.extensions.get("limiter")
        if limiter:
            limiter.limit("30/minute")(like_note)       # spam likes
            limiter.limit("1/minute")(view_note)        # vistas por IP
    except Exception:
        pass
    """)
p.write_text(s)
print("✓ routes.py: endpoints like/view + límites")
PY

# 3) DB: crear columnas si faltan
source venv/bin/activate
python - <<'PY'
from backend import create_app, db
from sqlalchemy import text
app = create_app()
with app.app_context():
    # SQLite: intenta añadir columnas si no existen
    eng = db.engine
    def add(col, ddl):
        try:
            eng.execute(text(f"ALTER TABLE note ADD COLUMN {col} {ddl};"))
            print(f"  + columna {col} creada")
        except Exception as e:
            print(f"  = columna {col} ya existe ({e.__class__.__name__})")
    add("likes", "INTEGER DEFAULT 0")
    add("views", "INTEGER DEFAULT 0")
print("✓ base de datos actualizada")
PY

# 4) FRONTEND: mostrar contadores y botón Like
cp -p frontend/js/app.js frontend/js/app.js.bak.$ts
python - <<'PY'
from pathlib import Path, re
p=Path("frontend/js/app.js"); s=p.read_text()

# Render de nota: añade likes y views + botón
s=re.sub(r"this.list.innerHTML = notes\.map\([^)]*\)\.join\(\"\"\);",
         """this.list.innerHTML = notes.map(n => `
  <li data-id="\${n.id}">
    <div class="note-text">\${n.text}</div>
    <div class="note-meta">
      <button class="like-btn">❤️ Like</button>
      <span class="counters">👍 \${n.likes||0} · 👁️ \${n.views||0}</span>
    </div>
  </li>`).join("");""",
         s)

# Wire buttons + ping de vista (1 vez por render)
if "bindItemEvents" not in s:
    s=s.replace("renderNotes(notes) {",
    """renderNotes(notes) {
    const once = new Set();""")
    s=s.replace("this.pagNav.innerHTML = \"\";",
    """this.pagNav.innerHTML = "";
    // eventos por item
    this.list.querySelectorAll("li").forEach(li=>{
      const id = li.getAttribute("data-id");
      const like = li.querySelector(".like-btn");
      like.onclick = async ()=>{
        const r = await fetch(`/api/notes/${id}/like`,{method:"POST"});
        if(r.ok){ const c = li.querySelector(".counters");
          const json = await r.json();
          c.textContent = `👍 ${json.likes} · ` + c.textContent.split('·')[1].trim();
        }
      };
      // registrar vista una sola vez por render
      if(!once.has(id)){
        once.add(id);
        fetch(`/api/notes/${id}/view`,{method:"POST"}).catch(()=>{});
      }
    });""")

p.write_text(s)
print("✓ app.js actualizado (UI likes/visitas)")
PY

# 5) CSS pequeño (si falta)
grep -q ".note-meta" frontend/css/styles.css || cat >> frontend/css/styles.css <<'CSS'

/* Meta de nota: likes/visitas */
.note-meta{display:flex;justify-content:space-between;align-items:center;margin-top:.4rem}
.like-btn{
  background:#ff00ff;color:#fff;border:none;border-radius:.6rem;padding:.35rem .7rem;
  cursor:pointer;transition:transform .1s;
}
.like-btn:hover{transform:scale(1.06)}
CSS

# 6) Reiniciar servidor
pkill -f waitress 2>/dev/null || true
python run.py &
echo "🚀  Servidor reiniciado. Abre la URL que imprime arriba."
