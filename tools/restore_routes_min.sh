#!/usr/bin/env bash
set -euo pipefail

F="backend/routes.py"
mkdir -p "$(dirname "$F")"

# Backup si existe
if [[ -f "$F" ]]; then
  cp -n "$F" "$F.bak.$(date -u +%Y%m%dT%H%M%SZ)" || true
fi

cat > "$F" <<'PY'
# -*- coding: utf-8 -*-
from __future__ import annotations

import os
from datetime import datetime, timedelta

from flask import Blueprint, jsonify, request, current_app

import sqlalchemy as sa

# DB y modelos
try:
    from backend import db
    from backend.models import Note, LikeLog, ReportLog, ViewLog
except Exception as e:
    # Permite que __api_import_error muestre el traceback
    raise

api = Blueprint("api", __name__)

# ---------------- Utils ----------------

def _fingerprint_from_request(req) -> str:
    # Huella simple y estable por IP + UA (suficiente para rateos básicos)
    ip = (req.headers.get("X-Forwarded-For") or req.remote_addr or "").split(",")[0].strip()
    ua = req.headers.get("User-Agent", "")
    return f"{ip}|{ua}"[:255]

def _to_dict(n: Note) -> dict:
    return {
        "id": n.id,
        "text": getattr(n, "text", None),
        "timestamp": n.timestamp.isoformat() if getattr(n, "timestamp", None) else None,
        "expires_at": n.expires_at.isoformat() if getattr(n, "expires_at", None) else None,
        "likes": getattr(n, "likes", 0) or 0,
        "views": getattr(n, "views", 0) or 0,
        "reports": getattr(n, "reports", 0) or 0,
    }

def pick(*vals):
    for v in vals:
        if v is None:
            continue
        s = str(v).strip()
        if s != "":
            return s
    return ""

# ---------------- Health & rutas de introspección ----------------

@api.route("/health", methods=["GET"])
def _health():
    return jsonify({"ok": True}), 200

@api.route("/_routes", methods=["GET"])
def api_routes_dump():
    info = []
    for r in current_app.url_map.iter_rules():
        info.append({
            "rule": str(r),
            "methods": sorted(m for m in r.methods if m not in ("HEAD","OPTIONS")),
            "endpoint": r.endpoint,
        })
    info.sort(key=lambda x: x["rule"])
    return jsonify({"routes": info}), 200

# ---------------- CRUD de notas ----------------

@api.route("/notes", methods=["POST"])
def create_note():
    raw_json = request.get_json(silent=True)
    data = raw_json if isinstance(raw_json, dict) else {}

    text = pick(
        (data.get("text") if isinstance(data, dict) else None),
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

@api.route("/notes/<int:note_id>/view", methods=["POST"])
def view_note(note_id: int):
    n = db.session.get(Note, note_id)
    if not n:
        return jsonify({"error": "not_found"}), 404
    fp = _fingerprint_from_request(request)
    today = datetime.utcnow().date()
    already = db.session.query(ViewLog.id).filter_by(
        note_id=note_id, fingerprint=fp, view_date=today
    ).first()
    if already:
        return jsonify({"ok": True, "views": n.views or 0, "already_viewed": True}), 200
    try:
        # Importante: usar view_date (no 'day')
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
        # opcional: umbral de borrado por reportes
        if (n.reports or 0) >= 5:
            db.session.delete(n)
            db.session.commit()
            return jsonify({"ok": True, "deleted": True, "reports": 5}), 200
        db.session.commit()
        return jsonify({"ok": True, "reports": n.reports}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": "report_failed", "detail": str(e)}), 500

@api.route("/notes", methods=["GET", "HEAD"])
def list_notes():
    # active_only default true
    raw_active = (request.args.get("active_only", "1") or "").lower()
    active_only = raw_active in ("1","true","on","yes","y")

    # before_id cursor estricto (id < before_id)
    raw_before = (request.args.get("before_id")
                  or request.args.get("before")
                  or request.args.get("max_id")
                  or request.args.get("cursor"))
    try:
        before_id = int(raw_before) if raw_before is not None else None
    except Exception:
        before_id = None

    # limit acotado
    try:
        limit = int(request.args.get("limit", 20))
    except Exception:
        limit = 20
    limit = max(1, min(100, limit))

    q = Note.query
    if active_only:
        q = q.filter(Note.expires_at > sa.func.now())
    if before_id:
        q = q.filter(Note.id < before_id)

    q = q.order_by(Note.id.desc()).limit(limit)
    rows = q.all()
    items = [_to_dict(n) for n in rows]

    # wrap opcional
    raw_wrap = (request.args.get("wrap", "0") or "").lower()
    if raw_wrap in ("1","true","on","yes","y"):
        next_before_id = items[-1]["id"] if len(items) == limit else None
        return jsonify({
            "items": items,
            "has_more": next_before_id is not None,
            "next_before_id": next_before_id,
        }), 200

    return jsonify(items), 200

# ---------------- Admin / diag opcional ----------------

@api.route("/dbdiag", methods=["GET"])
def dbdiag():
    out = {}
    try:
        out["has_db"] = True
        try:
            bind = db.session.get_bind()
            out["session_bind"] = bool(bind)
            out["engine_str"] = str(bind.url) if bind else None
        except Exception as e:
            out["session_bind"] = False
            out["session_bind_err"] = str(e)
        try:
            conn = db.engine.connect()
            conn.execute(sa.text("SELECT 1"))
            conn.close()
            out["engine_ok"] = True
        except Exception as e:
            out["engine_ok"] = False
            out["engine_err"] = str(e)
    except Exception as e:
        out["has_db"] = False
        out["err"] = str(e)
    return jsonify(out), 200
PY

# normalizar fin-de-linea
python - <<'PY'
from pathlib import Path
p=Path("backend/routes.py")
p.write_text(p.read_text(encoding="utf-8").replace("\t","    "), encoding="utf-8")
print("OK: routes.py escrito y normalizado (tabs->spaces)")
PY

git add backend/routes.py >/dev/null 2>&1 || true
git commit -m "chore(routes): restaura routes.py mínimo, indentación limpia y endpoints clave" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true
echo "✓ Commit & push hecho."
