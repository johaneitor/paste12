#!/usr/bin/env python3
import pathlib, py_compile, re

P = pathlib.Path("wsgiapp/__init__.py")
s = P.read_text(encoding="utf-8")
changed = False

def ensure(modline):
    global s, changed
    if modline not in s:
        # intenta pegarlo cerca del resto de imports
        if "import os" in s:
            s = s.replace("import os", "import os\n" + modline, 1)
        else:
            s = modline + "\n" + s
        changed = True

ensure("import json")
ensure("import time")
ensure("import os")

if "class _ExpiryCleaner" not in s:
    s += r"""

# === APPEND-ONLY: Expiry cleaner (sweep de vencidas; admin endpoints) ===
class _ExpiryCleaner:
    _last = 0

    def __init__(self, inner):
        self.inner = inner

    def _truth(self, v):
        return (v or "").strip().lower() in ("1","true","yes","on")

    def _interval(self, env):
        try:
            sec = int(os.environ.get("EXPIRE_SWEEP_INTERVAL_SEC", "600") or "600")
            return max(30, min(3600, sec))
        except Exception:
            return 600

    def _enabled(self, env):
        return not self._truth(os.environ.get("DISABLE_EXPIRE_SWEEP"))

    def _sweep_once(self, eng):
        # Crea índice si falta y borra vencidas en lote pequeño
        from sqlalchemy import text as T
        name = eng.dialect.name
        with eng.begin() as cx:
            try:
                cx.execute(T("CREATE INDEX IF NOT EXISTS ix_note_expires_at ON note(expires_at)"))
            except Exception:
                pass
            if name == "postgresql":
                q = """
                DELETE FROM note
                WHERE id = ANY(
                  ARRAY(SELECT id FROM note WHERE expires_at IS NOT NULL AND expires_at < NOW() LIMIT 500)
                )
                """
            else:
                # SQLite y otros
                q = "DELETE FROM note WHERE expires_at IS NOT NULL AND expires_at < CURRENT_TIMESTAMP LIMIT 500"
            r = cx.execute(T(q))
            try:
                return int(r.rowcount or 0)
            except Exception:
                return 0

    def _admin_ok(self, env):
        need = os.environ.get("ADMIN_TOKEN")
        got = (env.get("HTTP_X_ADMIN_TOKEN") or "").strip()
        return bool(need) and got == need

    def _force_expire(self, note_id, eng):
        from sqlalchemy import text as T
        with eng.begin() as cx:
            if eng.dialect.name == "postgresql":
                cx.execute(T("UPDATE note SET expires_at = NOW() - INTERVAL '1 second' WHERE id=:id"), {"id": note_id})
            else:
                cx.execute(T("UPDATE note SET expires_at = CURRENT_TIMESTAMP - 1 WHERE id=:id"), {"id": note_id})

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        method = (environ.get("REQUEST_METHOD") or "GET").upper()

        # Admin endpoints (protegidos)
        if path == "/api/admin/expire-now" and method == "POST":
            if not self._admin_ok(environ):
                body = json.dumps({"ok": False, "error": "forbidden"}).encode("utf-8")
                start_response("403 FORBIDDEN", [("Content-Type","application/json; charset=utf-8"),
                                                 ("Content-Length", str(len(body)))])
                return [body]
            try:
                from wsgiapp.__init__ import _engine
                n = self._sweep_once(_engine())
                body = json.dumps({"ok": True, "deleted": n}).encode("utf-8")
                start_response("200 OK", [("Content-Type","application/json; charset=utf-8"),
                                          ("Content-Length", str(len(body)))])
                return [body]
            except Exception as e:
                body = json.dumps({"ok": False, "error": str(e)}).encode("utf-8")
                start_response("500 ERROR", [("Content-Type","application/json; charset=utf-8"),
                                             ("Content-Length", str(len(body)))])
                return [body]

        if path.startswith("/api/admin/force-expire/") and method == "POST":
            if not self._admin_ok(environ):
                body = json.dumps({"ok": False, "error": "forbidden"}).encode("utf-8")
                start_response("403 FORBIDDEN", [("Content-Type","application/json; charset=utf-8"),
                                                 ("Content-Length", str(len(body)))])
                return [body]
            seg = path.rsplit("/", 1)[-1]
            try:
                note_id = int(seg)
            except Exception:
                note_id = None
            if not note_id:
                body = json.dumps({"ok": False, "error": "bad_id"}).encode("utf-8")
                start_response("400 BAD REQUEST", [("Content-Type","application/json; charset=utf-8"),
                                                   ("Content-Length", str(len(body)))])
                return [body]
            try:
                from wsgiapp.__init__ import _engine
                self._force_expire(note_id, _engine())
                body = json.dumps({"ok": True, "id": note_id}).encode("utf-8")
                start_response("200 OK", [("Content-Type","application/json; charset=utf-8"),
                                          ("Content-Length", str(len(body)))])
                return [body]
            except Exception as e:
                body = json.dumps({"ok": False, "error": str(e)}).encode("utf-8")
                start_response("500 ERROR", [("Content-Type","application/json; charset=utf-8"),
                                             ("Content-Length", str(len(body)))])
                return [body]

        # Sweep oportunista
        now = int(time.time())
        if self._enabled(environ) and now - _ExpiryCleaner._last >= self._interval(environ):
            _ExpiryCleaner._last = now
            try:
                from wsgiapp.__init__ import _engine
                self._sweep_once(_engine())
            except Exception:
                pass

        return self.inner(environ, start_response)
"""
    changed = True

# Hook outermost (una sola vez)
if "EXPIRY_CLEANER_WRAPPED = True" not in s:
    s += r"""
# --- envolver outermost: expiry cleaner ---
try:
    EXPIRY_CLEANER_WRAPPED
except NameError:
    try:
        app = _ExpiryCleaner(app)
    except Exception:
        pass
    EXPIRY_CLEANER_WRAPPED = True
"""
    changed = True

if not changed:
    print("OK: expiry cleaner ya estaba"); raise SystemExit(0)

P.write_text(s, encoding="utf-8")
py_compile.compile(str(P), doraise=True)
print("patched: expiry cleaner + admin endpoints")
