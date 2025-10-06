#!/usr/bin/env bash
set -euo pipefail
PY="wsgiapp/__init__.py"
test -f "$PY" || { echo "ERROR: no existe $PY"; exit 1; }

python - <<'PY'
import io, sys, re, py_compile
p="wsgiapp/__init__.py"
s=io.open(p,"r",encoding="utf-8").read()

BLOCK = '''\
# p12:BEGIN EXT REPORTS/VIEWS
# (idempotente) rutas: POST /api/notes/<int:nid>/report  y  POST /api/notes/<int:nid>/view
try:
    import os, json, time, uuid, hashlib, hmac, base64
    from flask import request, jsonify
    from sqlalchemy import text
except Exception as _e:
    pass

def _p12_uid():
    try:
        u = request.cookies.get("p12uid")
        if not u:
            u = request.headers.get("X-Client-Id") or (request.remote_addr or str(uuid.uuid4()))
        return u
    except Exception:
        return str(uuid.uuid4())

def _p12_bootstrap(app, db):
    try:
        with app.app_context():
            db.session.execute(text(\"\"\"\n                CREATE TABLE IF NOT EXISTS note_reports (\n                  note_id   INTEGER NOT NULL,\n                  reporter  TEXT    NOT NULL,\n                  ts        TIMESTAMP DEFAULT now(),\n                  CONSTRAINT uq_note_report UNIQUE(note_id, reporter)\n                )\n            \"\"\"))\n            db.session.execute(text(\"\"\"\n                CREATE TABLE IF NOT EXISTS note_views (\n                  note_id   INTEGER NOT NULL,\n                  viewer    TEXT    NOT NULL,\n                  last_seen TIMESTAMP DEFAULT now(),\n                  CONSTRAINT uq_note_view UNIQUE(note_id, viewer)\n                )\n            \"\"\"))\n            db.session.commit()\n    except Exception as e:\n        try:\n            print(\"[p12] WARN bootstrap:\", e, file=sys.stderr)\n        except Exception:\n            pass

def _p12_has_rule(app, rule, method):
    try:
        for r in app.url_map.iter_rules():
            if r.rule == rule and method in (r.methods or set()):
                return True
    except Exception:
        return False
    return False

def _p12_register(app, db):
    _p12_bootstrap(app, db)

    if not _p12_has_rule(app, '/api/notes/<int:nid>/report', 'POST'):
        @app.post('/api/notes/<int:nid>/report')
        def p12_report(nid):
            try:
                uid = _p12_uid()
                db.session.execute(text(\"\"\"\n                    INSERT INTO note_reports(note_id, reporter)\n                    VALUES (:nid, :uid)\n                    ON CONFLICT (note_id, reporter) DO NOTHING\n                \"\"\"), {\"nid\": int(nid), \"uid\": uid})\n                cnt = db.session.execute(text(\"SELECT COUNT(*) FROM note_reports WHERE note_id=:nid\"), {\"nid\": int(nid)}).scalar()\n                # mantener columna reports si existe\n                try:\n                    db.session.execute(text(\"UPDATE notes SET reports=:c WHERE id=:nid\"), {\"c\": cnt, \"nid\": int(nid)})\n                except Exception:\n                    pass\n                removed = (cnt >= 3)\n                if removed:\n                    try:\n                        db.session.execute(text(\"UPDATE notes SET removed=TRUE WHERE id=:nid\"), {\"nid\": int(nid)})\n                    except Exception:\n                        pass\n                db.session.commit()\n                return jsonify(ok=True, removed=removed, reports=cnt)\n            except Exception as e:\n                db.session.rollback()\n                return jsonify(ok=False, error=\"server_error\"), 500

    if not _p12_has_rule(app, '/api/notes/<int:nid>/view', 'POST'):
        @app.post('/api/notes/<int:nid>/view')
        def p12_view(nid):
            try:\n                uid = _p12_uid()\n                n = int(nid)\n                db.session.execute(text(\"\"\"\n                    INSERT INTO note_views(note_id, viewer, last_seen)\n                    VALUES (:nid, :uid, now())\n                    ON CONFLICT (note_id, viewer) DO UPDATE\n                       SET last_seen = CASE WHEN EXTRACT(EPOCH FROM (now() - note_views.last_seen)) > 21600\n                                             THEN now() ELSE note_views.last_seen END\n                \"\"\"), {\"nid\": n, \"uid\": uid})\n                # sumar view sólo si > 6h\n                delta = db.session.execute(text(\"\"\"\n                    SELECT (EXTRACT(EPOCH FROM (now() - last_seen)) > 21600)::int\n                    FROM note_views WHERE note_id=:nid AND viewer=:uid\n                \"\"\"), {\"nid\": n, \"uid\": uid}).scalar()\n                if delta == 1:\n                    try:\n                        db.session.execute(text(\"UPDATE notes SET views = COALESCE(views,0)+1 WHERE id=:nid\"), {\"nid\": n})\n                    except Exception:\n                        pass\n                db.session.commit()\n                return jsonify(ok=True)\n            except Exception:\n                db.session.rollback()\n                return jsonify(ok=False), 500

try:
    # requiere que existan app y db globales en este módulo
    if 'app' in globals() and 'db' in globals():
        _p12_register(app, db)
    else:
        try:\n            print('[p12] WARN: no app/db; skip registers', file=sys.stderr)\n        except Exception:\n            pass
except Exception:\n    pass
# p12:END EXT REPORTS/VIEWS
'''

if re.search(r'# p12:BEGIN EXT REPORTS/VIEWS', s):
    s = re.sub(r'# p12:BEGIN EXT REPORTS/VIEWS.*?# p12:END EXT REPORTS/VIEWS', BLOCK, s, flags=re.S)
else:
    if not s.endswith("\n"): s += "\n"
    s += "\n" + BLOCK + "\n"

io.open(p,"w",encoding="utf-8").write(s)
py_compile.compile(p, doraise=True)
print("PATCH_OK", p)
PY

python -m py_compile "$PY" >/dev/null && echo "OK: $PY compilado"
