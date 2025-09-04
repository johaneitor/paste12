#!/usr/bin/env python3
import re, sys, pathlib, py_compile

P = pathlib.Path("wsgiapp/__init__.py")
s = P.read_text(encoding="utf-8")
changed = []

# 0) imports seguros
def ensure_import(mod):
    global s
    if not re.search(rf'^\s*import\s+{mod}\b', s, flags=re.M):
        m = re.search(r'^(?:from[^\n]*\n|import[^\n]*\n)+', s, flags=re.M)
        s = (s[:m.end()] + f"import {mod}\n" + s[m.end():]) if m else (f"import {mod}\n{s}")
        changed.append(f"import {mod}")

for mod in ("os", "json", "hashlib"):
    ensure_import(mod)

# 1) inyectar clase si falta
if "class _LikesGuardV3" not in s:
    s += r"""

# === APPEND-ONLY: guard de likes V3 (1x persona, atómico y reversible) ===
class _LikesGuardV3:
    def __init__(self, inner):
        self.inner = inner

    def _fp(self, environ):
        # 1) fingerprint explícito
        fp = (environ.get("HTTP_X_FP") or "").strip()
        if fp:
            return fp[:128]
        # 2) IP (XFF primera) + UA
        xff = (environ.get("HTTP_X_FORWARDED_FOR") or "").split(",")[0].strip()
        ip  = xff or (environ.get("REMOTE_ADDR") or "").strip()
        ua  = (environ.get("HTTP_USER_AGENT") or "").strip()
        raw = f"{ip}|{ua}"
        import hashlib
        return hashlib.sha256(raw.encode("utf-8","ignore")).hexdigest()

    def _json(self, start_response, code, payload):
        import json
        body = json.dumps(payload, default=str).encode("utf-8")
        headers = [
            ("Content-Type","application/json; charset=utf-8"),
            ("Content-Length", str(len(body))),
            ("X-WSGI-Bridge","1"),
        ]
        start_response(f"{code} " + ("OK" if code==200 else "ERROR"), headers)
        return [body]

    def _bootstrap(self, eng):
        # Crea tabla e índice único si faltan (válido para pg/sqlite)
        from sqlalchemy import text as _text
        with eng.begin() as cx:
            cx.execute(_text("""
                CREATE TABLE IF NOT EXISTS like_log(
                    note_id INTEGER NOT NULL REFERENCES note(id) ON DELETE CASCADE,
                    fingerprint VARCHAR(128) NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """))
            cx.execute(_text("""
                CREATE UNIQUE INDEX IF NOT EXISTS uq_like_note_fp
                ON like_log(note_id, fingerprint)
            """))

    def _insert_once(self, cx, dialect, note_id, fp):
        from sqlalchemy import text as _text
        if dialect == "postgresql":
            res = cx.execute(_text(
                "INSERT INTO like_log(note_id, fingerprint) VALUES (:id,:fp) "
                "ON CONFLICT (note_id, fingerprint) DO NOTHING"
            ), {"id": note_id, "fp": fp})
            rc = getattr(res, "rowcount", 0) or 0
            return rc > 0
        elif dialect == "sqlite":
            res = cx.execute(_text(
                "INSERT OR IGNORE INTO like_log(note_id, fingerprint) VALUES (:id,:fp)"
            ), {"id": note_id, "fp": fp})
            rc = getattr(res, "rowcount", 0) or 0
            return rc > 0
        else:
            # genérico: intentar INSERT y atrapar unique
            try:
                cx.execute(_text(
                    "INSERT INTO like_log(note_id, fingerprint) VALUES (:id,:fp)"
                ), {"id": note_id, "fp": fp})
                return True
            except Exception:
                return False

    def _handle_like(self, environ, start_response, note_id):
        import os
        from sqlalchemy import text as _text
        # Flag reversible
        enabled = (environ.get("ENABLE_LIKES_DEDUPE") or os.getenv("ENABLE_LIKES_DEDUPE","1")).strip().lower() in ("1","true","yes","on")
        if not enabled:
            return self.inner(environ, start_response)

        try:
            from wsgiapp.__init__ import _engine
            eng = _engine()
            self._bootstrap(eng)
            fp = self._fp(environ)
            dialect = getattr(eng.dialect, "name", "")

            with eng.begin() as cx:
                inserted = self._insert_once(cx, dialect, note_id, fp)
                if inserted:
                    cx.execute(_text("UPDATE note SET likes = COALESCE(likes,0)+1 WHERE id=:id"), {"id": note_id})
                row = cx.execute(_text(
                    "SELECT id, COALESCE(likes,0) AS likes, COALESCE(views,0) AS views, COALESCE(reports,0) AS reports "
                    "FROM note WHERE id=:id"
                ), {"id": note_id}).mappings().first()
                if not row:
                    return self._json(start_response, 404, {"ok": False, "error": "not_found"})
                return self._json(start_response, 200, {
                    "ok": True,
                    "id": row["id"],
                    "likes": row["likes"],
                    "views": row["views"],
                    "reports": row["reports"],
                    "deduped": (not inserted),
                })
        except Exception as e:
            return self._json(start_response, 500, {"ok": False, "error": f"likes_guard_v3: {e}"})

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

# envolver una sola vez
try:
    _LIKES_GUARD_V3_APPLIED
except NameError:
    try:
        app = _LikesGuardV3(app)
    except Exception:
        pass
    _LIKES_GUARD_V3_APPLIED = True
"""
    changed.append("inject _LikesGuardV3")

# 2) escribir y compilar
P.write_text(s, encoding="utf-8")
try:
    py_compile.compile(str(P), doraise=True)
    print("patched:", ", ".join(changed) if changed else "no changes")
except Exception as e:
    print("✗ py_compile error:", e)
    sys.exit(2)
