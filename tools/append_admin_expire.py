#!/usr/bin/env python3
import pathlib, py_compile

P = pathlib.Path("wsgiapp/__init__.py")
s = P.read_text(encoding="utf-8")

if "class _AdminExpireWrapper" in s:
    print("ya estaba inyectado")
else:
    s += r"""

# === APPEND-ONLY: admin expire endpoints ===
#   - POST /api/admin/expire-now
#   - POST /api/admin/force-expire/<id>
class _AdminExpireWrapper:
    def __init__(self, inner):
        self.inner = inner

    def _json(self, start_response, code, payload):
        import json
        body = json.dumps(payload, default=str).encode('utf-8')
        start_response(f"{code} OK", [
            ("Content-Type","application/json; charset=utf-8"),
            ("Content-Length", str(len(body))),
            ("X-WSGI-Bridge","1"),
        ])
        return [body]

    def _forbidden(self, start_response, reason):
        return self._json(start_response, 403, {"ok": False, "error": reason})

    def _auth_ok(self, environ):
        import os
        token = (environ.get("HTTP_X_ADMIN_TOKEN") or "").strip()
        secrets = [
            os.getenv("ADMIN_TOKEN") or "",
            os.getenv("RENDER_ADMIN_TOKEN") or "",
            os.getenv("ADMIN_SECRET") or "",
        ]
        secret = ""
        for s in secrets:
            if s:
                secret = s
                break
        if not secret:
            return False, "admin_disabled"
        if token != secret:
            return False, "forbidden"
        return True, ""

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO","") or "")
        method = (environ.get("REQUEST_METHOD","GET") or "GET").upper()

        # POST /api/admin/expire-now
        if path == "/api/admin/expire-now" and method == "POST":
            ok, reason = self._auth_ok(environ)
            if not ok:
                return self._forbidden(start_response, reason)
            try:
                from sqlalchemy import text as _text
                from wsgiapp.__init__ import _engine
                eng = _engine()
                with eng.begin() as cx:
                    rows = cx.execute(_text(
                        "SELECT id FROM note WHERE expires_at IS NOT NULL AND expires_at <= CURRENT_TIMESTAMP"
                    )).fetchall()
                    ids = [r[0] for r in rows]
                    deleted = 0
                    for nid in ids:
                        cx.execute(_text("DELETE FROM note WHERE id=:id"), {"id": nid})
                        deleted += 1
                return self._json(start_response, 200, {"ok": True, "deleted": deleted})
            except Exception as e:
                return self._json(start_response, 500, {"ok": False, "error": str(e)})

        # POST /api/admin/force-expire/<id>
        if path.startswith("/api/admin/force-expire/") and method == "POST":
            ok, reason = self._auth_ok(environ)
            if not ok:
                return self._forbidden(start_response, reason)
            seg = path.rsplit("/", 1)[-1]
            try:
                nid = int(seg.strip("/"))
            except Exception:
                nid = None
            if not nid:
                return self._json(start_response, 400, {"ok": False, "error": "bad_id"})
            try:
                from sqlalchemy import text as _text
                from wsgiapp.__init__ import _engine
                eng = _engine()
                with eng.begin() as cx:
                    cx.execute(_text("UPDATE note SET expires_at=CURRENT_TIMESTAMP WHERE id=:id"), {"id": nid})
                return self._json(start_response, 200, {"ok": True, "id": nid})
            except Exception as e:
                return self._json(start_response, 500, {"ok": False, "error": str(e)})

        return self.inner(environ, start_response)

# Envolver como outermost (idempotente)
try:
    _ADMIN_EXPIRE_WRAPPED
except NameError:
    try:
        app = _AdminExpireWrapper(app)
    except Exception:
        pass
    _ADMIN_EXPIRE_WRAPPED = True
"""
    P.write_text(s, encoding="utf-8")
    print("patched: _AdminExpireWrapper añadido")

# sanity: compilar antes de commitear
py_compile.compile(str(P), doraise=True)
print("✓ py_compile OK")
