#!/usr/bin/env python3
import pathlib, re, sys, py_compile

P = pathlib.Path("wsgiapp/__init__.py")
s = P.read_text(encoding="utf-8")
changed = False

def ensure_imports(src: str) -> str:
    out = src
    if not re.search(r'^\s*import\s+os\b', out, re.M):
        out = re.sub(r'^(import[^\n]*\n)', r'\1import os\n', out, 1, re.M)
    # sqlalchemy.text alias
    if not re.search(r'from\s+sqlalchemy\s+import\s+text\s+as\s+_text', out):
        if re.search(r'from\s+sqlalchemy\s+import\s+text\b', out):
            out = re.sub(r'from\s+sqlalchemy\s+import\s+text\b',
                         'from sqlalchemy import text as _text', out, 1)
        elif re.search(r'^\s*from\s+sqlalchemy\s+import\b', out, re.M):
            out = re.sub(r'^\s*from\s+sqlalchemy\s+import\b',
                         'from sqlalchemy import text as _text\n\\g<0>', out, 1, re.M)
        else:
            out = re.sub(r'^(import[^\n]*\n)', r'\1from sqlalchemy import text as _text\n', out, 1, re.M)
    return out

s = ensure_imports(s)

if "class _LikesGuard" not in s:
    s += r"""

# === APPEND-ONLY: Likes 1×persona con dedupe + concurrencia segura ===
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

    def _bootstrap(self, cx):
        # Crea tabla/índice si faltan (idempotente)
        try:
            cx.execute(_text("""
                CREATE TABLE IF NOT EXISTS like_log(
                    id SERIAL PRIMARY KEY,
                    note_id INTEGER NOT NULL REFERENCES note(id) ON DELETE CASCADE,
                    fingerprint VARCHAR(128) NOT NULL,
                    created_at TIMESTAMPTZ DEFAULT NOW()
                )
            """))
        except Exception:
            # SQLite: SERIAL no existe; crea equivalente básico
            cx.execute(_text("""
                CREATE TABLE IF NOT EXISTS like_log(
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    note_id INTEGER NOT NULL,
                    fingerprint VARCHAR(128) NOT NULL,
                    created_at TEXT DEFAULT CURRENT_TIMESTAMP
                )
            """))
        # índice único
        try:
            cx.execute(_text("""
                CREATE UNIQUE INDEX IF NOT EXISTS uq_like_note_fp
                ON like_log(note_id, fingerprint)
            """))
        except Exception:
            pass

    def _db_is_sqlite(self, cx) -> bool:
        try:
            r = cx.execute(_text("SELECT sqlite_version()")).first()
            return bool(r)
        except Exception:
            return False

    def _handle_like(self, environ, start_response, note_id: int):
        # Feature flag reversible por header/env (ENABLE_LIKES_DEDUPE)
        enable = (environ.get("ENABLE_LIKES_DEDUPE") or
                  environ.get("HTTP_ENABLE_LIKES_DEDUPE") or
                  "1").strip().lower() in ("1","true","yes","on")
        if not enable:
            return self.inner(environ, start_response)

        fp = self._fp(environ)

        # Reutilizamos el engine del módulo
        try:
            from wsgiapp.__init__ import _engine
        except Exception:
            return self._json(start_response, 500, {"ok": False, "error": "_engine no disponible"})

        eng = _engine()
        try:
            with eng.begin() as cx:
                self._bootstrap(cx)

                # ¿existe?
                pre = cx.execute(_text(
                    "SELECT 1 FROM like_log WHERE note_id=:id AND fingerprint=:fp LIMIT 1"
                ), {"id": note_id, "fp": fp}).first()
                existed = bool(pre)

                if not existed:
                    # Insert seguro (Postgres/SQLite)
                    if self._db_is_sqlite(cx):
                        try:
                            cx.execute(_text(
                                "INSERT OR IGNORE INTO like_log(note_id, fingerprint) VALUES (:id, :fp)"
                            ), {"id": note_id, "fp": fp})
                        except Exception:
                            pass
                    else:
                        try:
                            cx.execute(_text(
                                "INSERT INTO like_log(note_id, fingerprint) VALUES (:id, :fp) "
                                "ON CONFLICT (note_id, fingerprint) DO NOTHING"
                            ), {"id": note_id, "fp": fp})
                        except Exception:
                            # Fallback si no soporta ON CONFLICT
                            try:
                                cx.execute(_text(
                                    "INSERT INTO like_log(note_id, fingerprint) VALUES (:id, :fp)"
                                ), {"id": note_id, "fp": fp})
                            except Exception:
                                pass

                # Recalcular likes desde log (corrige drift/concurrencia)
                cx.execute(_text(
                    "UPDATE note SET likes = (SELECT COUNT(*) FROM like_log WHERE note_id=:id) WHERE id=:id"
                ), {"id": note_id})

                row = cx.execute(_text(
                    "SELECT id, COALESCE(likes,0) AS likes, COALESCE(views,0) AS views, COALESCE(reports,0) AS reports FROM note WHERE id=:id"
                ), {"id": note_id}).mappings().first()

                if not row:
                    return self._json(start_response, 404, {"ok": False, "error": "not_found"})

                return self._json(start_response, 200, {
                    "ok": True, "id": row["id"], "likes": row["likes"],
                    "views": row["views"], "reports": row["reports"],
                    "deduped": existed
                })
        except Exception as e:
            return self._json(start_response, 500, {"ok": False, "error": str(e)})

    def __call__(self, environ, start_response):
        try:
            path   = (environ.get("PATH_INFO","") or "")
            method = (environ.get("REQUEST_METHOD","GET") or "GET").upper()

            # /api/notes/<id>/like
            if method == "POST" and path.startswith("/api/notes/") and path.endswith("/like"):
                mid = path[len("/api/notes/"):-len("/like")]
                try:
                    note_id = int(mid.strip("/"))
                except Exception:
                    note_id = None
                if note_id:
                    return self._handle_like(environ, start_response, note_id)

            # (opcional) alias /api/like/<id>
            if method == "POST" and path.startswith("/api/like/"):
                mid = path[len("/api/like/"):]
                try:
                    note_id = int(mid.strip("/"))
                except Exception:
                    note_id = None
                if note_id:
                    return self._handle_like(environ, start_response, note_id)

        except Exception:
            pass
        return self.inner(environ, start_response)
"""
    changed = True

if re.search(r'^\s*app\s*=\s*_LikesGuard\(app\)', s, re.M):
    pass
else:
    # Asegura que exista una 'app = ...' previa; si no, igual lo agregamos al final.
    s += r"""

# --- envolver con guard de likes 1×persona (outermost) ---
try:
    app = _LikesGuard(app)
except Exception:
    # si aún no existe app en este punto, el import falló; se ignora.
    pass
"""
    changed = True

if changed:
    s = s.rstrip() + "\n"
    P.write_text(s, encoding="utf-8")
    # Sanity de sintaxis
    py_compile.compile(str(P), doraise=True)
    print("patched: _LikesGuard añadido y aplicado")
else:
    print("no changes (ya aplicado)")
