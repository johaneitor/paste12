#!/usr/bin/env python3
import pathlib, re

P = pathlib.Path("wsgiapp/__init__.py")
s = P.read_text(encoding="utf-8")

# Evitar doble inyección
if "class _LikesGuard" in s and re.search(r"\bapp\s*=\s*_LikesGuard\(app\)", s):
    print("ya estaba inyectado")
else:
    s += r"""

# === APPEND-ONLY: Like 1x persona (dedupe por huella) ===
class _LikesGuard:
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
        raw = "|".join(parts).encode("utf-8", "ignore")
        return hashlib.sha256(raw).hexdigest()

    def _json(self, start_response, code, payload):
        import json
        body = json.dumps(payload, default=str).encode("utf-8")
        start_response(f"{code} " + ("OK" if code==200 else "ERROR"),
                       [("Content-Type","application/json; charset=utf-8"),
                        ("Content-Length", str(len(body))),
                        ("X-WSGI-Bridge","1")])
        return [body]

    def _ensure_schema(self, cx):
        from sqlalchemy import text as _text
        # Tabla e índice de dedupe (idempotente)
        cx.execute(_text("""
            CREATE TABLE IF NOT EXISTS like_log(
                id SERIAL PRIMARY KEY,
                note_id INTEGER NOT NULL REFERENCES note(id) ON DELETE CASCADE,
                fingerprint VARCHAR(128) NOT NULL,
                created_at TIMESTAMPTZ DEFAULT NOW()
            )
        """))
        cx.execute(_text("""
            CREATE UNIQUE INDEX IF NOT EXISTS uq_like_note_fp
            ON like_log(note_id, fingerprint)
        """))

    def _handle_like(self, environ, start_response, note_id):
        import os
        from sqlalchemy import text as _text
        try:
            # Reversible por flag (por defecto ON)
            enable = (os.getenv("ENABLE_LIKES_DEDUPE","1").strip().lower()
                      in ("1","true","yes","on"))
            if not enable:
                return self.inner(environ, start_response)

            fp = self._fp(environ)

            # Usamos el engine ya definido en este módulo
            eng = _engine()
            with eng.begin() as cx:
                self._ensure_schema(cx)

                got = cx.execute(_text(
                    "SELECT 1 FROM like_log WHERE note_id=:id AND fingerprint=:fp LIMIT 1"
                ), {"id": note_id, "fp": fp}).first()

                if not got:
                    # Primer like de esta huella → insert + UPDATE likes
                    try:
                        cx.execute(_text(
                            "INSERT INTO like_log(note_id, fingerprint) VALUES(:id,:fp)"
                        ), {"id": note_id, "fp": fp})
                    except Exception:
                        # Carrera contra UNIQUE → lo tratamos como dedupe
                        pass
                    cx.execute(_text(
                        "UPDATE note SET likes = COALESCE(likes,0)+1 WHERE id=:id"
                    ), {"id": note_id})

                row = cx.execute(_text(
                    "SELECT id, COALESCE(likes,0) AS likes, COALESCE(views,0) AS views, COALESCE(reports,0) AS reports "
                    "FROM note WHERE id=:id"
                ), {"id": note_id}).mappings().first()

                if not row:
                    return self._json(start_response, 404, {"ok": False, "error": "not_found"})

                payload = {
                    "ok": True,
                    "id": row["id"],
                    "likes": row["likes"],
                    "views": row["views"],
                    "reports": row["reports"],
                    "deduped": bool(got)
                }
                return self._json(start_response, 200, payload)
        except Exception as e:
            return self._json(start_response, 500, {"ok": False, "error": str(e)})

    def __call__(self, environ, start_response):
        try:
            path   = (environ.get("PATH_INFO","") or "")
            method = (environ.get("REQUEST_METHOD","GET") or "GET").upper()
            if method == "POST":
                # /api/notes/<id>/like  o  /api/like/<id>
                if path.startswith("/api/notes/") and path.endswith("/like"):
                    mid = path[len("/api/notes/"):-len("/like")]
                elif path.startswith("/api/like/"):
                    mid = path[len("/api/like/"):]
                else:
                    mid = None
                note_id = None
                if mid is not None:
                    try:
                        note_id = int(mid.strip("/"))
                    except Exception:
                        note_id = None
                if note_id:
                    return self._handle_like(environ, start_response, note_id)
        except Exception:
            pass
        return self.inner(environ, start_response)

# Montar como outermost (una vez)
try:
    app = _LikesGuard(app)
except Exception:
    pass
"""
    P.write_text(s, encoding="utf-8")
    print("patched: _LikesGuard append-only + montado")
