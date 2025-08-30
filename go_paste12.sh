#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
ROOT="$(pwd)"
echo "🚀 go_paste12 — dir: $ROOT"

# ---------- 0. Storage (para guardar logs en Downloads) ----------
if [ ! -d "$HOME/storage" ]; then
  echo "📁 Habilitando storage (solo primera vez)…"
  termux-setup-storage || true
fi

# ---------- 1. Parches de frontend (dedupe + /api/reports) ----------
if [ -x ./patch_frontend_v2.sh ]; then
  ./patch_frontend_v2.sh
else
  echo "ℹ️  patch_frontend_v2.sh no existe; creando uno mínimo…"
  cat > patch_frontend_v2.sh <<'MINI'
#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
bk(){ [ -f "$1" ] && cp -a "$1" "$1.bak.$(date +%s)" || true; }
find1(){ find . -type f -name "$1" | head -n1; }

ACT="$(find1 actions.js || true)"
AMN="$(find1 actions_menu.js || true)"
IDX="$(find1 index.html || true)"
if [ -n "$ACT" ]; then
  bk "$ACT"
  sed -E -i "s#fetch\\\(\`/api/notes/\\\$\{id\\\}/report\`[^)]*\\\)#fetch('/api/reports',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({content_id:String(id)})})#g" "$ACT" || true
fi
if [ -n "$AMN" ]; then
  bk "$AMN"
  sed -E -i "s#fetch\\\('/api/notes/\\\$\{id\\\}/report'[^)]*\\\)#fetch('/api/reports',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({content_id:String(id)})})#g" "$AMN" || true
fi
if [ -n "$IDX" ]; then
  bk "$IDX"
  sed -E -i 's/\?v=[^"]+/\?v=7/g' "$IDX"
fi
echo "✅ Frontend listo"
MINI
  chmod +x patch_frontend_v2.sh
  ./patch_frontend_v2.sh
fi

# ---------- 2. Migración SQLite (reports + flagged_content) ----------
SQL_FILE="migrate_reports.sql"
if [ ! -f "$SQL_FILE" ]; then
  cat > "$SQL_FILE" <<'SQL'
PRAGMA foreign_keys=ON;
CREATE TABLE IF NOT EXISTS reports(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  content_id TEXT NOT NULL,
  reporter_id TEXT NOT NULL,
  reason TEXT,
  ts DATETIME DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(content_id, reporter_id)
);
CREATE INDEX IF NOT EXISTS idx_reports_content ON reports(content_id);
CREATE TABLE IF NOT EXISTS flagged_content(
  content_id TEXT PRIMARY KEY,
  flagged_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
SQL
fi
if [ -f app.db ]; then
  sqlite3 app.db < "$SQL_FILE"
elif [ -f instance/app.db ]; then
  sqlite3 instance/app.db < "$SQL_FILE"
elif [ -f data/app.db ]; then
  sqlite3 data/app.db < "$SQL_FILE"
else
  echo "⚠️  No encontré app.db; creo app.db en raíz"
  sqlite3 app.db < "$SQL_FILE"
fi
echo "✅ Migración aplicada"

# ---------- 3. Backend Flask: añadir /api/reports si falta ----------
ROUTES="backend/routes.py"
if [ -f "$ROUTES" ]; then
  if ! grep -qE "/api/reports|@bp\.route\(\"/reports\"" "$ROUTES"; then
    cp -a "$ROUTES" "$ROUTES.bak.$(date +%s)"
    cat >> "$ROUTES" <<'PY'

# === paste12: /api/reports (mínimo, usa SQLite directo) ============
import sqlite3, os
from flask import request, jsonify
DB_PATH = os.getenv("PASTE12_DB", "app.db")

def _db_path():
    for p in ("app.db", "instance/app.db", "data/app.db"):
        if os.path.exists(os.path.join(os.getcwd(), p)): return p
    return "app.db"

def _conn():
    path = _db_path()
    conn = sqlite3.connect(path, check_same_thread=False)
    conn.execute("PRAGMA journal_mode=WAL;")
    conn.execute("PRAGMA synchronous=NORMAL;")
    conn.execute("PRAGMA busy_timeout=5000;")
    conn.row_factory = sqlite3.Row
    return conn

@bp.route("/reports", methods=["POST"])
def create_report_min():
    try:
        j = request.get_json(force=True, silent=True) or {}
        cid = str(j.get("content_id","")).strip()
        if not cid:
            return jsonify({"error":"content_id_required"}), 400
        fp = request.headers.get("X-Forwarded-For") or request.remote_addr or "anon"
        con = _conn()
        con.execute("INSERT OR IGNORE INTO reports(content_id, reporter_id, reason) VALUES(?,?,?)",
                    (cid, fp, j.get("reason")))
        con.commit()
        c = int(con.execute("SELECT COUNT(*) FROM reports WHERE content_id=?", (cid,)).fetchone()[0])
        con.close()
        deleted = False  # (opcional) acá podrías ocultar la nota si c>=5
        return jsonify({"ok": True, "count": c, "deleted": deleted}), 200
    except Exception as e:
        return jsonify({"error":"report_failed","detail":str(e)}), 500
PY
    echo "✅ routes.py: agregado endpoint /api/reports"
  else
    echo "ℹ️  routes.py ya tiene /api/reports"
  fi
else
  echo "⚠️  No encontré backend/routes.py — omito inyección Flask."
fi

# ---------- 4. Rate-limit básico con Flask-Limiter ----------
INIT="backend/__init__.py"
if [ -f "$INIT" ]; then
  if ! grep -q "from flask_limiter import Limiter" "$INIT"; then
    cp -a "$INIT" "$INIT.bak.$(date +%s)"
    awk '
      BEGIN{done=0}
      /^from flask/ && done==0 {print; print "from flask_limiter import Limiter\nfrom flask_limiter.util import get_remote_address"; done=1; next}
      {print}
    ' "$INIT" > "$INIT.tmp" && mv "$INIT.tmp" "$INIT"
    # Inicialización simple del limiter si no existe
    if ! grep -q "Limiter(" "$INIT"; then
      echo -e "\n# paste12 limiter init\nlimiter = Limiter(key_func=get_remote_address, default_limits=[])\n" >> "$INIT"
    fi
    echo "✅ __init__.py: import/inicialización Limiter"
  fi

  # Decorar like/report si no tienen límites en routes.py
  if [ -f "$ROUTES" ]; then
    if ! grep -q "@limiter.limit('1 per 10 seconds'" "$ROUTES"; then
      cp -a "$ROUTES" "$ROUTES.bak.$(date +%s).rl"
      sed -E -i "s#(@bp\.route\(\"/notes/<int:note_id>/like\"[^\n]*\)\n)def like_note#\1@limiter.limit('1 per 10 seconds')\n@limiter.limit('500 per day')\ndef like_note#g" "$ROUTES" || true
      sed -E -i "s#(@bp\.route\(\"/reports\"[^\n]*\)\n)def create_report_min#\1@limiter.limit('1 per 10 seconds')\n@limiter.limit('200 per day')\ndef create_report_min#g" "$ROUTES" || true
      echo "✅ routes.py: añadidos límites a like/report"
    fi
  fi
else
  echo "⚠️  No encontré backend/__init__.py — salteo limiter."
fi

# ---------- 5. Auditorías ----------
if [ -x ./post_audit_v2.sh ]; then
  ./post_audit_v2.sh || true
fi

if [ -x ./audit_paste12.sh ]; then
  ./audit_paste12.sh | tee ".audit_last.txt"
  # Guardar a Downloads
  TS="$(date +%F_%H%M)"
  DEST="$HOME/storage/downloads/audit_paste12_$TS.txt"
  cp -f ".audit_last.txt" "$DEST" && echo "📝 Audit → $DEST"
fi

# ---------- 6. Git commit + push ----------
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
git add backend/routes.py backend/__init__.py actions.js actions_menu.js index.html migrate_reports.sql || true
git commit -m "feat(sec): add /api/reports (Flask), migrate reports table, rate-limit like/report, normalize frontend versions" || true
git push origin "$BRANCH" || true

echo "✅ Done. Si usás un runner (gunicorn/waitress), reiniciá el proceso para tomar cambios."
