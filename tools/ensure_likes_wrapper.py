#!/usr/bin/env python3
import pathlib, re

P = pathlib.Path("wsgiapp/__init__.py")
s = P.read_text(encoding="utf-8")

need_write = False

# 0) asegurar import os (no rompe si ya está)
if not re.search(r'^\s*import\s+os\b', s, flags=re.M):
    s = re.sub(r'^(import[^\n]*\n)', r'\1import os\n', s, count=1, flags=re.M)
    need_write = True

# 1) clase _LikesWrapper (append-only)
if "class _LikesWrapper" not in s:
    s += r"""

# === APPEND-ONLY: Like 1x persona (dedupe por fingerprint) ===
class _LikesWrapper:
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
        return hashlib.sha256("|".join(parts).encode("utf-8","ignore")).hexdigest()

    def _json(self, start_response, code, payload):
        import json
        body = json.dumps(payload, default=str).encode("utf-8")
        start_response(f"{code} " + ("OK" if code==200 else "ERROR"),
                       [("Content-Type","application/json; charset=utf-8"),
                        ("Content-Length", str(len(body))),
                        ("X-WSGI-Bridge","1")])
        return [body]

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
            pass

    def _handle_like(self, environ, start_response, note_id):
        from sqlalchemy import text as _text
        enable = (environ.get("ENABLE_LIKES_DEDUPE") or
                  environ.get("HTTP_ENABLE_LIKES_DEDUPE") or
                  "1").strip().lower() in ("1","true","yes","on")
        if not enable:
            return self.inner(environ, start_response)
        try:
            fp = self._fp(environ)
            from wsgiapp.__init__ import _engine  # usa el engine del bridge
            eng = _engine()
            with eng.begin() as cx:
                self._bootstrap_like_log(cx)
                got = cx.execute(_text(
                    "SELECT 1 FROM like_log WHERE note_id=:id AND fingerprint=:fp LIMIT 1"
                ), {"id": note_id, "fp": fp}).first()
                if not got:
                    try:
                        cx.execute(_text(
                            "INSERT INTO like_log(note_id, fingerprint) VALUES(:id,:fp)"
                        ), {"id": note_id, "fp": fp})
                        cx.execute(_text(
                            "UPDATE note SET likes = COALESCE(likes,0)+1 WHERE id=:id"
                        ), {"id": note_id})
                    except Exception:
                        pass
                row = cx.execute(_text(
                    "SELECT id, COALESCE(likes,0) AS likes, COALESCE(views,0) AS views, COALESCE(reports,0) AS reports FROM note WHERE id=:id"
                ), {"id": note_id}).mappings().first()
                if not row:
                    return self._json(start_response, 404, {"ok": False, "error": "not_found"})
                return self._json(start_response, 200, {
                    "ok": True, "id": row["id"], "likes": row["likes"],
                    "views": row["views"], "reports": row["reports"],
                    "deduped": bool(got),
                })
        except Exception as e:
            return self._json(start_response, 500, {"ok": False, "error": str(e)})

    def __call__(self, environ, start_response):
        try:
            path   = (environ.get("PATH_INFO","") or "")
            method = (environ.get("REQUEST_METHOD","GET") or "GET").upper()
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
"""
    need_write = True

# 2) envolver la app (outermost), una sola vez
if "app = _LikesWrapper(app)" not in s:
    s += "\napp = _LikesWrapper(app)\n"
    need_write = True

if need_write:
    P.write_text(s, encoding="utf-8")
    print("patched: _LikesWrapper presente y app envuelta")
else:
    print("OK: _LikesWrapper ya estaba aplicado")
