#!/usr/bin/env python3
import pathlib

P = pathlib.Path("wsgiapp/__init__.py")
s = P.read_text(encoding="utf-8")

if "class _LikesWrapper" in s:
    print("ya estaba inyectado")
else:
    s += r"""

# === APPEND-ONLY: Like 1x persona (dedupe por fingerprint) ===
class _LikesWrapper:
    def __init__(self, inner):
        self.inner = inner

    # Huella: respeta X-FP si viene; si no, hash(IP+UA)
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

    def _json(self, start_response, status_code, payload):
        import json
        body = json.dumps(payload, default=str).encode("utf-8")
        start_response(f"{status_code} " + ("OK" if status_code == 200 else "ERROR"), [
            ("Content-Type","application/json; charset=utf-8"),
            ("Content-Length", str(len(body))),
            ("X-WSGI-Bridge","1"),
        ])
        return [body]

    # Crea tabla/índice si faltan (idempotente)
    def _bootstrap_like_log(self, cx):
        from sqlalchemy import text as _text
        try:
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
        except Exception:
            # Si no es Postgres o ya existe, seguimos
            pass

    def _handle_like(self, environ, start_response, note_id):
        from sqlalchemy import text as _text
        # Flag maestro: reversible sin tocar código
        enable = (environ.get("ENABLE_LIKES_DEDUPE") or
                  environ.get("HTTP_ENABLE_LIKES_DEDUPE") or
                  "1").strip().lower() in ("1","true","yes","on")
        if not enable:
            return self.inner(environ, start_response)

        try:
            fp = self._fp(environ)
            # usa el engine existente del bridge
            from wsgiapp.__init__ import _engine  # noqa
            eng = _engine()
            with eng.begin() as cx:
                self._bootstrap_like_log(cx)

                # ¿Ya likeó esta huella?
                got = cx.execute(_text(
                    "SELECT 1 FROM like_log WHERE note_id=:id AND fingerprint=:fp LIMIT 1"
                ), {"id": note_id, "fp": fp}).first()

                if not got:
                    # Intento insertar huella (si colisiona unique → no pasa nada)
                    try:
                        cx.execute(_text(
                            "INSERT INTO like_log(note_id, fingerprint) VALUES(:id,:fp)"
                        ), {"id": note_id, "fp": fp})
                        cx.execute(_text(
                            "UPDATE note SET likes = COALESCE(likes,0)+1 WHERE id=:id"
                        ), {"id": note_id})
                    except Exception:
                        pass  # carrera: otro proceso se adelantó

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
                    "deduped": bool(got),
                })
        except Exception as e:
            return self._json(start_response, 500, {"ok": False, "error": str(e)})

    def __call__(self, environ, start_response):
        try:
            path   = (environ.get("PATH_INFO","") or "")
            method = (environ.get("REQUEST_METHOD","GET") or "GET").upper()
            # match: /api/notes/<id>/like
            if method == "POST" and path.startswith("/api/notes/") and path.endswith("/like"):
                seg = path[len("/api/notes/"):-len("/like")]
                try:
                    note_id = int(seg.strip("/"))
                except Exception:
                    note_id = None
                if note_id:
                    return self._handle_like(environ, start_response, note_id)
        except Exception:
            pass
        return self.inner(environ, start_response)

# envolver como capa más externa (una sola vez)
try:
    app = _LikesWrapper(app)
except Exception:
    pass
"""
    P.write_text(s, encoding="utf-8"))
    print("patched: _LikesWrapper añadido (append-only)")
