#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"
FILE="wsgiapp/__init__.py"

[ -f "$FILE" ] || { echo "[!] No existe $FILE"; exit 1; }
echo "[+] Backup de $FILE"
cp -f "$FILE" "$FILE.bak.$(date +%s)"

cat > "$FILE" <<'PY'
from __future__ import annotations
import os, hashlib
from datetime import datetime, timedelta
from flask import Flask, Blueprint, jsonify, request

# --- 1) Obtener app base: intentar render_entry.app; si falla, crear Flask() mínima
try:
    from render_entry import app as app  # si tu entrypoint existe
except Exception:
    app = Flask(__name__)

# --- 2) SQLAlchemy propio del bridge, siempre ligado a 'app'
try:
    from flask_sqlalchemy import SQLAlchemy
except Exception as e:
    # Si no está instalado, exponemos error claro
    bp_err = Blueprint("bridge_probe", __name__)
    @bp_err.get("/api/health")
    def _health_no_sa():
        return jsonify(ok=False, error="flask_sqlalchemy_not_installed", detail=str(e)), 500
    app.register_blueprint(bp_err, url_prefix="/api")
    # export 'app' igualmente
    # (Render levantará /api/health con error explícito)
    # fin
else:
    def _normalize_dburi(uri: str | None) -> str:
        if not uri:
            return "sqlite:///app.db"
        if uri.startswith("postgres://"):
            return "postgresql://" + uri[len("postgres://"):]
        return uri

    app.config["SQLALCHEMY_DATABASE_URI"] = _normalize_dburi(os.environ.get("DATABASE_URL"))
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    db = SQLAlchemy(app)

    # --- 3) Modelo mínimo (compatible con tu Note)
    class Note(db.Model):
        __tablename__ = "note"
        id = db.Column(db.Integer, primary_key=True)
        text = db.Column(db.Text, nullable=False)
        timestamp = db.Column(db.DateTime, nullable=False, index=True)
        expires_at = db.Column(db.DateTime, nullable=False, index=True)
        likes = db.Column(db.Integer, default=0, nullable=False)
        views = db.Column(db.Integer, default=0, nullable=False)
        reports = db.Column(db.Integer, default=0, nullable=False)
        author_fp = db.Column(db.String(64), nullable=False, default="noctx", index=True)

    # --- 4) Helpers
    def _now() -> datetime:
        return datetime.utcnow()

    def _fp(req: request) -> str:
        try:
            ip = req.headers.get("X-Forwarded-For","") or req.headers.get("CF-Connecting-IP","") or (req.remote_addr or "")
            ua = req.headers.get("User-Agent","")
            salt = os.environ.get("FP_SALT","")
            return hashlib.sha256(f"{ip}|{ua}|{salt}".encode()).hexdigest()[:32]
        except Exception:
            return "noctx"

    def _note_json(n: Note, now: datetime | None = None) -> dict:
        now = now or _now()
        toiso = lambda d: (d.isoformat() if d else None)
        return {
            "id": n.id,
            "text": n.text,
            "timestamp": toiso(getattr(n,"timestamp",None)),
            "expires_at": toiso(getattr(n,"expires_at",None)),
            "likes": getattr(n,"likes",0),
            "views": getattr(n,"views",0),
            "reports": getattr(n,"reports",0),
            "author_fp": getattr(n,"author_fp",None),
            "now": now.isoformat(),
        }

    # --- 5) Blueprint del bridge (idempotente)
    bp = Blueprint("bridge_probe", __name__)

    @bp.get("/health")
    def _health():
        # etiqueta útil para saber desde dónde sirve
        note = "bridge-self-sqlalchemy"
        return jsonify(ok=True, note=note), 200

    @bp.get("/debug-urlmap")
    def debug_urlmap():
        rules = []
        for r in app.url_map.iter_rules():
            methods = sorted([m for m in r.methods if m not in ("HEAD","OPTIONS")])
            rules.append({"rule": str(r), "endpoint": r.endpoint, "methods": methods})
        return jsonify(ok=True, rules=rules), 200

    @bp.get("/notes")
    def bridge_list_notes():
        try:
            try:
                page = max(1, int(request.args.get("page", 1)))
            except Exception:
                page = 1
            q = Note.query.order_by(Note.timestamp.desc())
            items = q.limit(20).offset((page-1)*20).all()
            return jsonify([_note_json(n) for n in items]), 200
        except Exception as e:
            return jsonify(ok=False, error="list_failed", detail=str(e)), 500

    @bp.post("/notes")
    def bridge_create_note():
        from sqlalchemy.exc import SQLAlchemyError
        try:
            data = request.get_json(silent=True) or {}
            text = (data.get("text") or "").strip()
            if not text:
                return jsonify(error="text required"), 400
            try:
                hours = int(data.get("hours", 24))
            except Exception:
                hours = 24
            hours = min(168, max(1, hours))
            now = _now()
            n = Note(
                text=text,
                timestamp=now,
                expires_at=now + timedelta(hours=hours),
                author_fp=_fp(request),
            )
            db.session.add(n)
            db.session.commit()
            return jsonify(_note_json(n, now)), 201
        except SQLAlchemyError as e:
            db.session.rollback()
            return jsonify(ok=False, error="create_failed", detail=str(e)), 500
        except Exception as e:
            return jsonify(ok=False, error="create_failed", detail=str(e)), 500

    @bp.get("/notes/diag")
    def bridge_notes_diag():
        try:
            cnt = Note.query.count()
            first = Note.query.order_by(Note.id.asc()).first()
            out = {"count": int(cnt)}
            if first is not None:
                out["first"] = _note_json(first)
            return jsonify(ok=True, diag=out), 200
        except Exception as e:
            return jsonify(ok=False, error="diag_failed", detail=str(e)), 500

    # --- 6) Registrar y crear tablas
    try:
        app.register_blueprint(bp, url_prefix="/api")
    except Exception:
        pass
    try:
        with app.app_context():
            db.create_all()
    except Exception:
        pass

# Exportar 'app' para gunicorn wsgiapp:app
PY

echo "[+] Commit & push"
git add -A
git commit -m "bridge: use self-bound SQLAlchemy (DATABASE_URL or sqlite), add /api/notes & diag & debug-urlmap" || true
git push -u --force-with-lease origin "$(git rev-parse --abbrev-ref HEAD)"

echo
echo "[i] Tras el redeploy de Render, verifica:"
cat <<'CMD'
curl -s https://paste12-rmsk.onrender.com/api/health | jq .
curl -s https://paste12-rmsk.onrender.com/api/debug-urlmap | jq .
curl -s https://paste12-rmsk.onrender.com/api/notes/diag | jq .
curl -i -s 'https://paste12-rmsk.onrender.com/api/notes?page=1' | sed -n '1,120p'
curl -i -s -X POST -H 'Content-Type: application/json' \
  -d '{"text":"bridge-self-sqlalchemy","hours":24}' \
  https://paste12-rmsk.onrender.com/api/notes | sed -n '1,160p'
CMD
