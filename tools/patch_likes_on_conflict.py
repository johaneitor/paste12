#!/usr/bin/env python3
import pathlib, re

P = pathlib.Path("wsgiapp/__init__.py")
s = P.read_text(encoding="utf-8")

if "class _LikesGuardOC" in s:
    print("ya estaba inyectado")
else:
    s += r"""

# === APPEND-ONLY: Guard de likes 1×persona con ON CONFLICT (reversible por flag) ===
class _LikesGuardOC:
    def __init__(self, inner):
        self.inner = inner

    def _fp(self, environ):
        import hashlib
        fp = (environ.get("HTTP_X_FP") or "").strip()
        if fp:
            return fp[:128]
        parts = [
            (environ.get("HTTP_X_FORWARDED_FOR","").split(",")[0] or "").strip(),
            (environ.get("REMOTE_ADDR","") or "").strip(),
            (environ.get("HTTP_USER_AGENT","") or "").strip(),
        ]
        raw = "|".join(parts).encode("utf-8","ignore")
        return hashlib.sha256(raw).hexdigest()

    def _json(self, start_response, code, payload):
        import json
        body = json.dumps(payload, default=str).encode("utf-8")
        start_response(f"{code} OK", [
            ("Content-Type","application/json; charset=utf-8"),
            ("Content-Length", str(len(body))),
            ("X-WSGI-Bridge","1"),
        ])
        return [body]

    def _bootstrap_like_log(self, cx):
        from sqlalchemy import text as _text
        # Postgres
        try:
            cx.execute(_text("""
                CREATE TABLE IF NOT EXISTS like_log(
                    id SERIAL PRIMARY KEY,
                    note_id INTEGER NOT NULL REFERENCES note(id) ON DELETE CASCADE,
                    fingerprint VARCHAR(128) NOT NULL,
                    created_at TIMESTAMPTZ DEFAULT NOW()
                )"""))
        except Exception:
            # SQLite (fallback)
            try:
                cx.execute(_text("""
                    CREATE TABLE IF NOT EXISTS like_log(
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        note_id INTEGER NOT NULL,
                        fingerprint VARCHAR(128) NOT NULL,
                        created_at TEXT DEFAULT CURRENT_TIMESTAMP
                    )"""))
            except Exception:
                pass
        # Índice único (necesario para ON CONFLICT)
        try:
            cx.execute(_text("""CREATE UNIQUE INDEX IF NOT EXISTS uq_like_note_fp
                                ON like_log(note_id, fingerprint)"""))
        except Exception:
            pass

    def _handle_like(self, environ, start_response, note_id):
        import os
        from sqlalchemy import text as _text
        if (environ.get("ENABLE_LIKES_DEDUPE") or os.getenv("ENABLE_LIKES_DEDUPE","1")
            ).strip().lower() not in ("1","true","yes","on"):
            return self.inner(environ, start_response)

        try:
            from wsgiapp.__init__ import _engine
            eng = _engine()
            fp = self._fp(environ)
            with eng.begin() as cx:
                self._bootstrap_like_log(cx)
                # Intento de inserción; si ya existe, r.rowcount será 0
                inserted = False
                try:
                    r = cx.execute(_text("""
                        INSERT INTO like_log(note_id, fingerprint)
                        VALUES (:id,:fp)
                        ON CONFLICT (note_id, fingerprint) DO NOTHING
                    """), {"id": note_id, "fp": fp})
                    # En algunos drivers rowcount puede venir -1; verificamos existencia
                    if r.rowcount and r.rowcount > 0:
                        inserted = True
                    else:
                        got = cx.execute(_text(
                            "SELECT 1 FROM like_log WHERE note_id=:id AND fingerprint=:fp LIMIT 1"
                        ), {"id": note_id, "fp": fp}).first()
                        inserted = (got is None)
                except Exception:
                    # Si el dialecto no soporta ON CONFLICT, probamos insert plano y atrapamos unique
                    try:
                        cx.execute(_text(
                            "INSERT INTO like_log(note_id, fingerprint) VALUES (:id,:fp)"
                        ), {"id": note_id, "fp": fp})
                        inserted = True
                    except Exception:
                        inserted = False

                if inserted:
                    cx.execute(_text(
                        "UPDATE note SET likes = COALESCE(likes,0)+1 WHERE id=:id"
                    ), {"id": note_id})

                row = cx.execute(_text(
                    "SELECT id, COALESCE(likes,0) AS likes, COALESCE(views,0) AS views, COALESCE(reports,0) AS reports FROM note WHERE id=:id"
                ), {"id": note_id}).mappings().first()
                if not row:
                    return self._json(start_response, 404, {"ok": False, "error": "not_found"})
                return self._json(start_response, 200, {
                    "ok": True,
                    "id": row["id"],
                    "likes": row["likes"],
                    "views": row["views"],
                    "reports": row["reports"],
                    "deduped": not inserted
                })
        except Exception as e:
            return self._json(start_response, 500, {"ok": False, "error": str(e)})

    def __call__(self, environ, start_response):
        try:
            path = (environ.get("PATH_INFO","") or "")
            method = (environ.get("REQUEST_METHOD","GET") or "GET").upper()
            if method == "POST" and path.startswith("/api/notes/") and path.endswith("/like"):
                seg = path[len("/api/notes/"):-len("/like")]
                try:
                    nid = int(seg.strip("/"))
                except Exception:
                    nid = None
                if nid:
                    return self._handle_like(environ, start_response, nid)
        except Exception:
            pass
        return self.inner(environ, start_response)

# Envolver app una sola vez
try:
    _LIKES_OC_WRAPPED
except NameError:
    try:
        app = _LikesGuardOC(app)
    except Exception:
        pass
    _LIKES_OC_WRAPPED = True
"""
    P.write_text(s, encoding="utf-8")
    print("patched: _LikesGuardOC append-only")
