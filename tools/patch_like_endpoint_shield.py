#!/usr/bin/env python3
import pathlib, shutil, py_compile

W = pathlib.Path("wsgiapp/__init__.py")
s = W.read_text(encoding="utf-8")
changed = False

if "class _LikeEndpointShield" not in s:
    s += r"""

# === LikeEndpointShield: maneja POST /api/notes/:id/like con dedupe 1×persona ===
class _LikeEndpointShield:
    def __init__(self, inner):
        self.inner = inner

    # JSON propio (no dependemos de helpers internos)
    def _json(self, start_response, code, payload):
        import json
        body = json.dumps(payload, default=str).encode("utf-8")
        start_response(f"{code} OK", [
            ("Content-Type","application/json; charset=utf-8"),
            ("Content-Length", str(len(body))),
            ("X-WSGI-Bridge","1"),
        ])
        return [body]

    def _fp(self, env):
        import hashlib
        fp = (env.get("HTTP_X_FP") or "").strip()
        if fp:
            return fp[:128]
        parts = [
            (env.get("HTTP_X_FORWARDED_FOR","").split(",")[0] or "").strip(),
            (env.get("REMOTE_ADDR","") or "").strip(),
            (env.get("HTTP_USER_AGENT","") or "").strip(),
        ]
        raw = "|".join(parts).encode("utf-8","ignore")
        return hashlib.sha256(raw).hexdigest()

    def _bootstrap_like_log(self, cx):
        # Crea tabla/índice únicos si no existen (SQLite/Postgres)
        from sqlalchemy import text as T
        try:
            cx.execute(T("""
                CREATE TABLE IF NOT EXISTS like_log(
                  id INTEGER PRIMARY KEY,
                  note_id INTEGER NOT NULL REFERENCES note(id) ON DELETE CASCADE,
                  fingerprint VARCHAR(128) NOT NULL,
                  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
                )
            """))
        except Exception:
            pass
        try:
            cx.execute(T("""CREATE UNIQUE INDEX IF NOT EXISTS uq_like_note_fp
                            ON like_log(note_id, fingerprint)"""))
        except Exception:
            pass

    def __call__(self, environ, start_response):
        try:
            path = (environ.get("PATH_INFO") or "")
            method = (environ.get("REQUEST_METHOD","GET") or "GET").upper()

            # Intercepta SOLO el endpoint de like
            if method == "POST" and path.startswith("/api/notes/") and path.endswith("/like"):
                try:
                    seg = path[len("/api/notes/"):-len("/like")].strip("/")
                    note_id = int(seg)
                except Exception:
                    return self._json(start_response, 400, {"ok": False, "error": "bad_note_id"})

                # banderas (puedes desactivar dedupe por env)
                import os
                enabled = (os.getenv("ENABLE_LIKES_DEDUPE","1").lower() in ("1","true","yes","on"))

                from sqlalchemy import text as T
                from wsgiapp.__init__ import _engine  # usa el engine del app

                fp = self._fp(environ)
                try:
                    with _engine().begin() as cx:
                        self._bootstrap_like_log(cx)
                        inserted = True
                        if enabled:
                            # Intento de inserción; si choca unique, dedupe
                            try:
                                cx.execute(T(
                                    "INSERT INTO like_log(note_id, fingerprint) VALUES (:id,:fp)"
                                ), {"id": note_id, "fp": fp})
                            except Exception:
                                inserted = False
                        # Sólo sumamos si no fue deduplicado
                        if inserted:
                            cx.execute(T(
                                "UPDATE note SET likes = COALESCE(likes,0)+1 WHERE id=:id"
                            ), {"id": note_id})
                        row = cx.execute(T(
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
                            "deduped": (not inserted) if enabled else None,
                        })
                except Exception as e:
                    return self._json(start_response, 500, {"ok": False, "error": f"like_failed: {e}"})
        except Exception:
            # En cualquier error del shield, dejamos pasar al inner.
            pass
        return self.inner(environ, start_response)
"""

    changed = True

if "_LIKE_EP_SHIELDED = True" not in s:
    s += r"""
# --- outermost wrap: like shield (idempotente) ---
try:
    _LIKE_EP_SHIELDED
except NameError:
    try:
        app = _LikeEndpointShield(app)
    except Exception:
        pass
    _LIKE_EP_SHIELDED = True
"""
    changed = True

if changed:
    bak = W.with_suffix(".py.like_shield.bak")
    if not bak.exists():
        shutil.copyfile(W, bak)
    W.write_text(s, encoding="utf-8")
    print("patched: _LikeEndpointShield añadido")
else:
    print("OK: like shield ya presente")

py_compile.compile(str(W), doraise=True)
print("✓ py_compile OK")
