#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
cd "$(dirname "$0")"
ts=$(date +%s)

# Backups
cp -p backend/routes.py "backend/routes.py.bak.$ts" 2>/dev/null || true
cp -p frontend/index.html "frontend/index.html.bak.$ts" 2>/dev/null || true

# 1) Backend: rutas con LikeLog/ReportLog y huella por usuario
cat > backend/routes.py <<'PY'
from flask import Blueprint, request, jsonify
from datetime import datetime, timezone, timedelta
from hashlib import sha256
from sqlalchemy.exc import IntegrityError

from .models import Note, LikeLog, ReportLog
from . import db

bp = Blueprint("api", __name__, url_prefix="/api")

def _serialize(n: Note):
    now = datetime.now(timezone.utc)
    rem = max(0, int((n.expires_at - now).total_seconds())) if n.expires_at else 0
    return {
        "id": n.id,
        "text": n.text,
        "timestamp": n.timestamp.isoformat() if n.timestamp else None,
        "expires_at": n.expires_at.isoformat() if n.expires_at else None,
        "remaining_seconds": rem,
        "likes": int(getattr(n, "likes", 0) or 0),
        "views": int(getattr(n, "views", 0) or 0),
        "reports": int(getattr(n, "reports", 0) or 0),
    }

def _fingerprint():
    # 1) Preferir token de cliente
    tok = (request.headers.get("X-User-Token") or request.cookies.get("p12") or "").strip()
    if tok:
        return tok[:128]
    # 2) Huella derivada (IP+UA)
    ua = request.headers.get("User-Agent", "")
    ip = request.headers.get("X-Forwarded-For", request.remote_addr or "")
    return sha256(f"{ip}|{ua}".encode("utf-8")).hexdigest()

@bp.get("/notes")
def get_notes():
    page = max(int(request.args.get("page", 1) or 1), 1)
    per_page = min(int(request.args.get("per_page", 10) or 10), 50)
    now = datetime.now(timezone.utc)
    q = Note.query.filter(Note.expires_at > now).order_by(Note.timestamp.desc())
    p = q.paginate(page=page, per_page=per_page, error_out=False)
    return jsonify({"items": [_serialize(n) for n in p.items], "page": p.page, "pages": p.pages, "total": p.total})

@bp.post("/notes")
def create_note():
    data = request.get_json(silent=True) or {}
    text = (data.get("text") or "").strip()
    if not text:
        return jsonify({"error": "Texto requerido"}), 400

    dur = str(data.get("duration", "")).strip().lower()
    HMAP = {"12h":12, "1d":24, "24h":24, "7d":168}
    if isinstance(data.get("hours"), (int, float)) and data["hours"] > 0:
        hours = int(data["hours"])
    elif dur.endswith("h") and dur[:-1].isdigit():
        hours = int(dur[:-1])
    else:
        hours = HMAP.get(dur, 24*7)
    hours = max(1, min(hours, 24*30))

    now = datetime.now(timezone.utc)
    n = Note(text=text, timestamp=now, expires_at=now + timedelta(hours=hours))
    db.session.add(n)
    db.session.commit()
    return jsonify(_serialize(n)), 201

@bp.post("/notes/<int:note_id>/like")
def like_note(note_id: int):
    n = Note.query.get_or_404(note_id)
    fp = _fingerprint()

    # ¿ya likeó?
    if LikeLog.query.filter_by(note_id=n.id, fingerprint=fp).first():
        return jsonify({"likes": n.likes, "already_liked": True})

    try:
        db.session.add(LikeLog(note_id=n.id, fingerprint=fp))
        n.likes = (n.likes or 0) + 1
        db.session.commit()
        return jsonify({"likes": n.likes, "already_liked": False})
    except IntegrityError:
        db.session.rollback()
        n = Note.query.get(note_id)
        return jsonify({"likes": n.likes, "already_liked": True})

@bp.post("/notes/<int:note_id>/view")
def view_note(note_id: int):
    n = Note.query.get_or_404(note_id)
    n.views = (n.views or 0) + 1
    db.session.commit()
    return jsonify({"views": n.views})

@bp.post("/notes/<int:note_id>/report")
def report_note(note_id: int):
    n = Note.query.get_or_404(note_id)
    fp = _fingerprint()

    # ¿ya reportó?
    if ReportLog.query.filter_by(note_id=n.id, fingerprint=fp).first():
        return jsonify({"reports": n.reports, "already_reported": True, "deleted": False})

    try:
        db.session.add(ReportLog(note_id=n.id, fingerprint=fp))
        n.reports = (n.reports or 0) + 1
        if n.reports >= 5:
            db.session.delete(n)
            db.session.commit()
            return jsonify({"deleted": True, "reports": 0, "already_reported": False})
        db.session.commit()
        return jsonify({"deleted": False, "reports": n.reports, "already_reported": False})
    except IntegrityError:
        db.session.rollback()
        n = Note.query.get(note_id)
        return jsonify({"deleted": False, "reports": n.reports, "already_reported": True})
PY

# 2) Frontend: token persistente y cabecera X-User-Token en todos los fetch
mkdir -p frontend/js
cat > frontend/js/client_fp.js <<'JS'
(function(){
  function uuid(){
    if (window.crypto?.randomUUID) return crypto.randomUUID();
    const a = new Uint8Array(16);
    (window.crypto||{}).getRandomValues?.(a);
    return Array.from(a).map(b=>b.toString(16).padStart(2,'0')).join('');
  }
  let t = localStorage.getItem('p12');
  if (!t){ t = uuid(); localStorage.setItem('p12', t); }
  // expón por si se necesita
  window.p12Token = t;

  // Parchea fetch para añadir la cabecera X-User-Token
  const orig = window.fetch;
  window.fetch = function(input, init){
    init = init || {};
    const headers = new Headers(init.headers || {});
    headers.set('X-User-Token', t);
    init.headers = headers;
    return orig(input, init);
  };
  console.log('[client_fp] token listo');
})();
JS

# 3) Inyectar client_fp.js antes de app.js si existe, si no, antes de </body>
if grep -q 'js/app\.js' frontend/index.html; then
  perl -0777 -pe 's#(<script[^>]*src="js/app\.js[^"]*"[^>]*>\s*</script>)#<script src="js/client_fp.js?v='"$ts"'"></script>\n\1#i' -i frontend/index.html
else
  perl -0777 -pe 's#</body>#  <script src="js/client_fp.js?v='"$ts"'"></script>\n</body>#i' -i frontend/index.html
fi

# 4) Chequeo rápido de backend
python -m compileall -q backend
python - <<'PY'
from backend import create_app
app = create_app()
print("✅ create_app() OK — rutas con like/report por persona activas")
PY

# 5) Commit + push (forza redeploy)
git add backend/routes.py frontend/js/client_fp.js frontend/index.html
git commit -m "feat(like/report): 1 por persona usando LikeLog/ReportLog + token cliente (X-User-Token)" || true
git push -u origin "$(git rev-parse --abbrev-ref HEAD)"

echo "🚀 Subido. Tras el deploy, abre tu URL con /?v=$(date +%s) para saltar caché."
