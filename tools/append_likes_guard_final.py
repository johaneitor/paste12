#!/usr/bin/env python3
import pathlib, re, sys, py_compile
P = pathlib.Path("wsgiapp/__init__.py")
s = P.read_text(encoding="utf-8")
changed = False

# Asegurar imports mínimos (idempotente)
for mod in ("os","json","hashlib"):
    if not re.search(rf'^\s*import\s+{mod}\b', s, re.M):
        s = f"import {mod}\n{s}"
        changed = True

# Bloque principal (usar r''' … ''' para permitir """ adentro)
if "class _LikesGuardFinal" not in s:
    s += r'''
# === APPEND-ONLY: Guard final de likes 1×persona (CDN-friendly) ===
class _LikesGuardFinal:
    def __init__(self, inner):
        self.inner = inner

    def _fp(self, env):
        fp = (env.get("HTTP_X_FP") or "").strip()
        if fp:
            return fp[:128]
        ip = (
            (env.get("HTTP_CF_CONNECTING_IP") or "").strip()
            or (env.get("HTTP_TRUE_CLIENT_IP") or "").strip()
            or (env.get("HTTP_X_REAL_IP") or "").strip()
            or (env.get("HTTP_X_FORWARDED_FOR") or "").split(",")[0].strip()
            or (env.get("REMOTE_ADDR") or "").strip()
        )
        ua = (env.get("HTTP_USER_AGENT") or "").strip()
        raw = f"{ip}|{ua}".encode("utf-8","ignore")
        import hashlib
        return hashlib.sha256(raw).hexdigest()

    def _json(self, start_response, code, payload):
        import json
        body = json.dumps(payload, default=str).encode("utf-8")
        start_response(f"{code} OK", [
            ("Content-Type","application/json; charset=utf-8"),
            ("Content-Length", str(len(body))),
            ("Cache-Control","no-store, no-cache, must-revalidate, max-age=0"),
        ])
        return [body]

    def _bootstrap(self, cx):
        from sqlalchemy import text as T
        try:
            cx.execute(T("""
                CREATE TABLE IF NOT EXISTS like_log(
                  id SERIAL PRIMARY KEY,
                  note_id INTEGER NOT NULL REFERENCES note(id) ON DELETE CASCADE,
                  fingerprint VARCHAR(128) NOT NULL,
                  created_at TIMESTAMPTZ DEFAULT NOW()
                );
            """))
        except Exception:
            pass
        try:
            cx.execute(T("""
                CREATE UNIQUE INDEX IF NOT EXISTS uq_like_note_fp
                  ON like_log(note_id, fingerprint);
            """))
        except Exception:
            pass

    def _handle(self, env, start_response, note_id):
        try:
            from sqlalchemy import text as T
            from wsgiapp.__init__ import _engine
            fp = self._fp(env)
            with _engine().begin() as cx:
                self._bootstrap(cx)
                inserted = False
                try:
                    cx.execute(T(
                      "INSERT INTO like_log(note_id, fingerprint) VALUES (:id,:fp)"
                    ), {"id": note_id, "fp": fp})
                    inserted = True
                except Exception:
                    inserted = False
                if inserted:
                    cx.execute(T(
                      "UPDATE note SET likes=COALESCE(likes,0)+1 WHERE id=:id"
                    ), {"id": note_id})
                row = cx.execute(T(
                  "SELECT id, COALESCE(likes,0) AS likes, COALESCE(views,0) AS views, COALESCE(reports,0) AS reports FROM note WHERE id=:id"
                ), {"id": note_id}).mappings().first()
                if not row:
                    return self._json(start_response, 404, {"ok": False, "error": "not_found"})
                return self._json(start_response, 200, {
                    "ok": True, "id": row["id"],
                    "likes": row["likes"], "views": row["views"], "reports": row["reports"],
                    "deduped": (not inserted),
                })
        except Exception as e:
            return self._json(start_response, 500, {"ok": False, "error": str(e)})

    def __call__(self, environ, start_response):
        try:
            path = (environ.get("PATH_INFO","") or "")
            method = (environ.get("REQUEST_METHOD","GET") or "GET").upper()
            if method == "POST" and path.startswith("/api/notes/") and path.endswith("/like"):
                mid = path[len("/api/notes/"):-len("/like")]
                try:
                    nid = int(mid.strip("/"))
                except Exception:
                    nid = None
                if nid:
                    return self._handle(environ, start_response, nid)
        except Exception:
            pass
        return self.inner(environ, start_response)
'''
    changed = True

# Envolver una sola vez (outermost)
if "_LIKES_GUARD_FINAL = True" not in s:
    s += r'''
# --- envolver outermost: likes guard final ---
try:
    _LIKES_GUARD_FINAL
except NameError:
    try:
        app = _LikesGuardFinal(app)
    except Exception:
        pass
    _LIKES_GUARD_FINAL = True
'''
    changed = True

if not changed:
    print("OK: _LikesGuardFinal ya aplicado"); sys.exit(0)

P.write_text(s, encoding="utf-8")
py_compile.compile(str(P), doraise=True)
print("patched: _LikesGuardFinal + imports")
