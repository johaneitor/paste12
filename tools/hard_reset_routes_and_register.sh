#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"

ROUTES="backend/routes.py"
RUNPY="run.py"
LOG=".tmp/paste12.log"

echo "[+] Backups"
cp "$ROUTES" "$ROUTES.bak.$(date +%s)" 2>/dev/null || true
cp "$RUNPY"   "$RUNPY.bak.$(date +%s)" 2>/dev/null || true

###############################################################################
# 1) Reescribir backend/routes.py con una versión mínima y correcta
###############################################################################
cat > "$ROUTES" <<'PY'
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Optional

from flask import Blueprint, jsonify, request
from backend.models import db, Note
from backend.utils.fingerprint import client_fingerprint

bp = Blueprint("api", __name__)

def _now() -> datetime:
    return datetime.now(timezone.utc)

def _note_json(n: Note, now: Optional[datetime] = None) -> dict:
    if now is None:
        now = _now()
    return {
        "id": n.id,
        "text": n.text,
        "timestamp": n.timestamp.isoformat() if getattr(n, "timestamp", None) else None,
        "expires_at": n.expires_at.isoformat() if getattr(n, "expires_at", None) else None,
        "likes": getattr(n, "likes", 0),
        "views": getattr(n, "views", 0),
        "reports": getattr(n, "reports", 0),
    }

@bp.route("/health", methods=["GET"])
def health():
    return jsonify({"ok": True}), 200

@bp.route("/notes", methods=["GET"])
def list_notes():
    try:
        page = int(request.args.get("page", 1))
    except Exception:
        page = 1
    page = max(1, page)
    q = Note.query.order_by(Note.timestamp.desc())
    items = q.limit(20).offset((page - 1) * 20).all()
    return jsonify([_note_json(n, _now()) for n in items]), 200

@bp.route("/notes", methods=["POST"])
def create_note():
    data = request.get_json(silent=True) or {}
    text = (data.get("text") or "").strip()
    if not text:
        return jsonify({"error": "text required"}), 400
    try:
        hours = int(data.get("hours", 24))
    except Exception:
        hours = 24
    hours = min(168, max(1, hours))
    now = _now()
    n = Note(text=text, timestamp=now, expires_at=now + timedelta(hours=hours))
    # Fallback si el hook no setea author_fp
    try:
        if not getattr(n, "author_fp", None):
            n.author_fp = client_fingerprint()
    except Exception:
        pass
    db.session.add(n)
    db.session.commit()
    return jsonify(_note_json(n, now)), 201

@bp.route("/notes/<int:note_id>/like", methods=["POST"])
def like_note(note_id: int):
    n = Note.query.get_or_404(note_id)
    n.likes = (n.likes or 0) + 1
    db.session.commit()
    return jsonify({"ok": True, "likes": n.likes}), 200

@bp.route("/notes/<int:note_id>/report", methods=["POST"])
def report_note(note_id: int):
    n = Note.query.get_or_404(note_id)
    n.reports = (n.reports or 0) + 1
    db.session.commit()
    return jsonify({"ok": True, "reports": n.reports}), 200

@bp.route("/notes/<int:note_id>/view", methods=["POST"])
def view_note(note_id: int):
    n = Note.query.get_or_404(note_id)
    n.views = (n.views or 0) + 1
    db.session.commit()
    return jsonify({"ok": True, "views": n.views}), 200
PY

###############################################################################
# 2) Asegurar import y registro del blueprint en run.py (idempotente)
###############################################################################
if ! grep -q "from backend.routes import bp as api_bp" "$RUNPY"; then
  awk 'NR==1{print "from backend.routes import bp as api_bp"; print; next} {print}' "$RUNPY" > "$RUNPY.tmp" && mv "$RUNPY.tmp" "$RUNPY"
  echo "[+] Agregado import de blueprint en run.py"
fi

if ! grep -q "app.register_blueprint(api_bp" "$RUNPY"; then
  # Insertar después de la primera aparición de "app =" o al inicio si no existe
  if grep -n "app\s*=" "$RUNPY" >/dev/null; then
    LN="$(grep -n "app\s*=" "$RUNPY" | head -1 | cut -d: -f1)"
    awk -v ln="$LN" 'NR==ln{print; print "try:\n    app.register_blueprint(api_bp, url_prefix=\"/api\")\nexcept Exception as e:\n    try:\n        app.logger.error(\"No se pudo registrar blueprint API: %s\", e)\n    except Exception:\n        print(\"ERROR registrando blueprint API:\", e)"; next} {print}' "$RUNPY" > "$RUNPY.tmp" && mv "$RUNPY.tmp" "$RUNPY"
  else
    awk 'NR==1{print "try:\n    app.register_blueprint(api_bp, url_prefix=\"/api\")\nexcept Exception as e:\n    try:\n        app.logger.error(\"No se pudo registrar blueprint API: %s\", e)\n    except Exception:\n        print(\"ERROR registrando blueprint API:\", e)"; print; next} {print}' "$RUNPY" > "$RUNPY.tmp" && mv "$RUNPY.tmp" "$RUNPY"
  fi
  echo "[+] Registrado blueprint en run.py (url_prefix=/api)"
fi

# Garantizar import del hook (por si no está)
if ! grep -q "backend\.models_hooks" "$RUNPY"; then
  awk 'NR==1{print "import backend.models_hooks  # hook author_fp"; print; next} {print}' "$RUNPY" > "$RUNPY.tmp" && mv "$RUNPY.tmp" "$RUNPY"
  echo "[+] Import de hooks en run.py"
fi

###############################################################################
# 3) Reiniciar y smokes
###############################################################################
pkill -f "python .*run.py" 2>/dev/null || true
: > "$LOG" || true
nohup python "$RUNPY" >"$LOG" 2>&1 &
sleep 2

echo "[+] URL MAP runtime:"
python - <<'PY'
import importlib
app=getattr(importlib.import_module("run"),"app",None)
rules=[(str(r),sorted([m for m in r.methods if m not in("HEAD","OPTIONS")]),r.endpoint) for r in app.url_map.iter_rules()]
for rule,methods,ep in sorted(rules): print(f"{rule:30s}  {','.join(methods):10s}  {ep}")
print()
print("CHECKS:")
print(" - /api/health GET ->", any(r for r in rules if r[0]=="/api/health" and "GET" in r[1]))
print(" - /api/notes  GET ->", any(r for r in rules if r[0]=="/api/notes" and "GET" in r[1]))
print(" - /api/notes  POST->", any(r for r in rules if r[0]=="/api/notes" and "POST" in r[1]))
print(" - NO like_note on /api/notes ->", not any(r for r in rules if r[0]=="/api/notes" and r[2].endswith("like_note")))
PY

PORT="$(grep -Eo '127\.0\.0\.1:[0-9]+' "$LOG" 2>/dev/null | tail -n1 | cut -d: -f2 || echo 8000)"
echo "[i] PORT_LOCAL=$PORT"

echo "[+] Smoke GET /api/notes"
curl -i -s "http://127.0.0.1:$PORT/api/notes?page=1" | sed -n '1,80p'
echo
echo "[+] Smoke POST /api/notes"
curl -i -s -X POST -H "Content-Type: application/json" -d '{"text":"hard-reset-ok","hours":24}' "http://127.0.0.1:$PORT/api/notes" | sed -n '1,120p'
echo
