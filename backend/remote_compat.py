import os
from flask import Blueprint, request, jsonify
from sqlalchemy import create_engine, text

DATABASE_URL = os.environ.get("DATABASE_URL")
engine = create_engine(DATABASE_URL) if DATABASE_URL else None

bp = Blueprint("compat", __name__, url_prefix="/api")

def _patch_schema():
    if not engine: return
    with engine.begin() as con:
        con.execute(text("""
            CREATE TABLE IF NOT EXISTS like_log(
              id SERIAL PRIMARY KEY,
              note_id INTEGER NOT NULL,
              fingerprint VARCHAR(128) NOT NULL,
              created_at TIMESTAMPTZ DEFAULT NOW()
            );
        """))
        con.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS uq_like_note_fp ON like_log(note_id, fingerprint);"))

        con.execute(text("""
            CREATE TABLE IF NOT EXISTS report_log(
              id SERIAL PRIMARY KEY,
              note_id INTEGER NOT NULL,
              fingerprint VARCHAR(128) NOT NULL,
              created_at TIMESTAMPTZ DEFAULT NOW()
            );
        """))
        con.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS uq_report_note_fp ON report_log(note_id, fingerprint);"))

        con.execute(text("""
            CREATE TABLE IF NOT EXISTS view_log(
              id SERIAL PRIMARY KEY,
              note_id INTEGER NOT NULL,
              fingerprint VARCHAR(128) NOT NULL,
              created_at TIMESTAMPTZ DEFAULT NOW()
            );
        """))
        con.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS uq_view_note_fp ON view_log(note_id, fingerprint);"))

        # columnas que usa el código nuevo
        con.execute(text("ALTER TABLE IF EXISTS note ADD COLUMN IF NOT EXISTS author_fp VARCHAR(128);"))
        # por compatibilidad con esquemas viejos (si tu tabla es notes)
        con.execute(text("ALTER TABLE IF EXISTS notes ADD COLUMN IF NOT EXISTS author_fp VARCHAR(128);"))

@bp.record_once
def _on_load(setup_state):
    try:
        _patch_schema()
    except Exception:
        pass

def _fp(req):
    return req.headers.get("X-Forwarded-For") or req.remote_addr or "anon"

@bp.post("/notes/<int:note_id>/like")
def like_note(note_id: int):
    if not engine: return jsonify({"error":"no_db"}), 500
    fp = _fp(request)
    with engine.begin() as con:
        con.execute(text("INSERT INTO like_log(note_id, fingerprint) VALUES(:n, :f) ON CONFLICT DO NOTHING"),
                    {"n": note_id, "f": fp})
        cnt = con.execute(text("SELECT COUNT(*) FROM like_log WHERE note_id=:n"), {"n": note_id}).scalar_one()
    return jsonify({"ok": True, "likes": int(cnt), "id": note_id}), 200

@bp.post("/reports")
def create_report():
    if not engine: return jsonify({"error":"no_db"}), 500
    j = request.get_json(silent=True) or {}
    cid = int(j.get("content_id") or 0)
    if cid <= 0: return jsonify({"error":"content_id_required"}), 400
    fp = _fp(request)
    deleted = False
    with engine.begin() as con:
        con.execute(text("INSERT INTO report_log(note_id, fingerprint) VALUES(:n, :f) ON CONFLICT DO NOTHING"),
                    {"n": cid, "f": fp})
        c = con.execute(text("SELECT COUNT(*) FROM report_log WHERE note_id=:n"), {"n": cid}).scalar_one()
        if c >= 5:
            # intentar en ambas tablas por compatibilidad
            con.execute(text("DELETE FROM note  WHERE id=:n"),  {"n": cid})
            con.execute(text("DELETE FROM notes WHERE id=:n"), {"n": cid})
            deleted = True
    return jsonify({"ok": True, "count": int(c), "deleted": deleted}), 200

@bp.post("/notes/<int:note_id>/report")
def report_alias(note_id: int):
    # alias hacia /api/reports
    return create_report.__wrapped__()  # usa el mismo handler
