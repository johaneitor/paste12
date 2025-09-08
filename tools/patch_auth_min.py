#!/usr/bin/env python3
import pathlib, re, sys, json, base64, hashlib, secrets, shutil, py_compile
W = pathlib.Path("wsgiapp/__init__.py")
s = W.read_text(encoding="utf-8")
raw = s
changed = False

if "class _AuthEndpoints" not in s:
    s += r"""

# ================== APPEND-ONLY: AUTH MIN ==================
# Tablas: auth_user, auth_session
# Endpoints: POST /api/auth/register | POST /api/auth/login | POST /api/auth/logout | GET /api/auth/me
# Hash: PBKDF2-HMAC-SHA256 con salt aleatorio (formato: pbkdf2$sha256$iters$salt$hash)

def _p12_pbkdf2_hash(secret: str, iters: int = 200_000) -> str:
    import os, hashlib, base64
    salt = os.urandom(16)
    dk = hashlib.pbkdf2_hmac("sha256", secret.encode("utf-8"), salt, iters, dklen=32)
    return "pbkdf2$sha256$%d$%s$%s" % (
        iters,
        base64.urlsafe_b64encode(salt).decode().rstrip("="),
        base64.urlsafe_b64encode(dk).decode().rstrip("="),
    )

def _p12_pbkdf2_verify(secret: str, stored: str) -> bool:
    import base64, hashlib
    try:
        scheme, algo, iters_s, salt_b64, hash_b64 = stored.split("$", 4)
        if scheme != "pbkdf2" or algo != "sha256": return False
        iters = int(iters_s)
        salt = base64.urlsafe_b64decode(salt_b64 + "==")
        expect = base64.urlsafe_b64decode(hash_b64 + "==")
        dk = hashlib.pbkdf2_hmac("sha256", secret.encode("utf-8"), salt, iters, dklen=32)
        return secrets.compare_digest(dk, expect)
    except Exception:
        return False

class _AuthEndpoints:
    def __init__(self, inner):
        self.inner = inner

    # --- DB bootstrap (idempotente) ---
    def _boot(self, cx):
        from sqlalchemy import text as T
        try:
            cx.execute(T("""
                CREATE TABLE IF NOT EXISTS auth_user(
                  id SERIAL PRIMARY KEY,
                  username VARCHAR(50) UNIQUE NOT NULL,
                  pass_hash TEXT NOT NULL,
                  q1_hash TEXT NOT NULL,
                  q2_hash TEXT NOT NULL,
                  q3_hash TEXT NOT NULL,
                  created_at TIMESTAMPTZ DEFAULT NOW()
                )
            """))
        except Exception:
            pass
        try:
            cx.execute(T("""
                CREATE TABLE IF NOT EXISTS auth_session(
                  token VARCHAR(200) PRIMARY KEY,
                  user_id INTEGER NOT NULL REFERENCES auth_user(id) ON DELETE CASCADE,
                  created_at TIMESTAMPTZ DEFAULT NOW(),
                  expires_at TIMESTAMPTZ
                )
            """))
        except Exception:
            pass

    # --- helpers de cuerpo/cookie/json ---
    def _read_body(self, env):
        try:
            length = int(env.get("CONTENT_LENGTH") or "0")
        except Exception:
            length = 0
        data = (env["wsgi.input"].read(length) if length>0 else b"")
        ctype = (env.get("CONTENT_TYPE") or "").lower()
        if "application/json" in ctype:
            try:
                return True, json.loads(data.decode("utf-8"))
            except Exception:
                return True, {}
        else:
            # form-urlencoded
            try:
                from urllib.parse import parse_qs
                qs = parse_qs(data.decode("utf-8"), keep_blank_values=True)
                obj = {k: (v[0] if isinstance(v, list) and v else "") for k, v in qs.items()}
                return False, obj
            except Exception:
                return False, {}
    def _json(self, start_response, code, payload, cookies=None):
        body = json.dumps(payload, default=str).encode("utf-8")
        headers = [("Content-Type","application/json; charset=utf-8"),
                   ("Content-Length", str(len(body))),
                   ("Cache-Control","no-store, no-cache, must-revalidate, max-age=0"),
                   ("X-WSGI-Bridge","1")]
        for c in (cookies or []):
            headers.append(("Set-Cookie", c))
        start_response(f"{code} OK", headers)
        return [body]
    def _cookie_get(self, env, name):
        raw = env.get("HTTP_COOKIE") or ""
        for part in raw.split(";"):
            k, sep, v = part.strip().partition("=")
            if k == name and sep:
                return v
        return None
    def _make_session_cookie(self, token):
        # 30 días
        return f"p12_s={token}; Path=/; HttpOnly; SameSite=Lax; Max-Age=2592000"

    # --- rutas ---
    def _register(self, env, start_response):
        from sqlalchemy import text as T
        from wsgiapp.__init__ import _engine
        is_json, payload = self._read_body(env)
        u = (payload.get("username") or "").strip()
        p = (payload.get("password") or "").strip()
        q1 = (payload.get("q1") or "").strip()
        q2 = (payload.get("q2") or "").strip()
        q3 = (payload.get("q3") or "").strip()

        # validaciones mínimas
        import re
        if not re.fullmatch(r"[A-Za-z0-9_\-]{3,30}", u):
            return self._json(start_response, 400, {"ok": False, "error": "bad_username"})
        if len(p) < 8:
            return self._json(start_response, 400, {"ok": False, "error": "weak_password"})
        if not (q1 and q2 and q3):
            return self._json(start_response, 400, {"ok": False, "error": "questions_required"})

        ph = _p12_pbkdf2_hash(p)
        # hashear respuestas para no guardar texto plano
        h1 = _p12_pbkdf2_hash(q1.lower())
        h2 = _p12_pbkdf2_hash(q2.lower())
        h3 = _p12_pbkdf2_hash(q3.lower())

        try:
            with _engine().begin() as cx:
                self._boot(cx)
                cx.execute(T("INSERT INTO auth_user(username,pass_hash,q1_hash,q2_hash,q3_hash) VALUES(:u,:p,:a,:b,:c)"),
                           {"u": u, "p": ph, "a": h1, "b": h2, "c": h3})
            return self._json(start_response, 201, {"ok": True})
        except Exception as e:
            # conflicto de username u otro
            return self._json(start_response, 409, {"ok": False, "error": "user_exists_or_db", "detail": str(e)})

    def _login(self, env, start_response):
        from sqlalchemy import text as T
        from wsgiapp.__init__ import _engine
        is_json, payload = self._read_body(env)
        u = (payload.get("username") or "").strip()
        p = (payload.get("password") or "").strip()
        if not u or not p:
            return self._json(start_response, 400, {"ok": False, "error": "missing_fields"})
        with _engine().begin() as cx:
            self._boot(cx)
            row = cx.execute(T("SELECT id, pass_hash FROM auth_user WHERE username=:u"), {"u": u}).first()
            if not row:
                return self._json(start_response, 403, {"ok": False, "error": "invalid_credentials"})
            uid, stored = int(row[0]), row[1]
            if not _p12_pbkdf2_verify(p, stored):
                return self._json(start_response, 403, {"ok": False, "error": "invalid_credentials"})
            token = secrets.token_urlsafe(32)
            cx.execute(T("INSERT INTO auth_session(token,user_id,expires_at) VALUES(:t,:u, NOW() + INTERVAL '30 days')"),
                       {"t": token, "u": uid})
        cookie = self._make_session_cookie(token)
        return self._json(start_response, 200, {"ok": True, "token": token, "user": {"id": uid, "username": u}}, cookies=[cookie])

    def _me(self, env, start_response):
        from sqlalchemy import text as T
        from wsgiapp.__init__ import _engine
        # token: cookie o Authorization: Bearer
        tok = self._cookie_get(env, "p12_s")
        if not tok:
            auth = env.get("HTTP_AUTHORIZATION") or ""
            if auth.lower().startswith("bearer "):
                tok = auth.split(None,1)[1].strip()
        if not tok:
            return self._json(start_response, 401, {"ok": False, "error": "no_token"})
        with _engine().begin() as cx:
            self._boot(cx)
            row = cx.execute(T("""
                SELECT u.id, u.username
                FROM auth_session s
                JOIN auth_user u ON u.id = s.user_id
                WHERE s.token=:t AND (s.expires_at IS NULL OR s.expires_at > NOW())
            """), {"t": tok}).mappings().first()
            if not row:
                return self._json(start_response, 401, {"ok": False, "error": "invalid_token"})
            return self._json(start_response, 200, {"ok": True, "user": {"id": row["id"], "username": row["username"]}})

    def _logout(self, env, start_response):
        from sqlalchemy import text as T
        from wsgiapp.__init__ import _engine
        tok = self._cookie_get(env, "p12_s")
        if not tok:
            auth = env.get("HTTP_AUTHORIZATION") or ""
            if auth.lower().startswith("bearer "):
                tok = auth.split(None,1)[1].strip()
        with _engine().begin() as cx:
            self._boot(cx)
            if tok:
                cx.execute(T("DELETE FROM auth_session WHERE token=:t"), {"t": tok})
        # Cookie de invalidación
        dead = "p12_s=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0"
        return self._json(start_response, 200, {"ok": True}, cookies=[dead])

    def __call__(self, env, start_response):
        try:
            path = (env.get("PATH_INFO") or "")
            method = (env.get("REQUEST_METHOD") or "GET").upper()
            if path == "/api/auth/register" and method == "POST":
                return self._register(env, start_response)
            if path == "/api/auth/login" and method == "POST":
                return self._login(env, start_response)
            if path == "/api/auth/me" and method == "GET":
                return self._me(env, start_response)
            if path == "/api/auth/logout" and method == "POST":
                return self._logout(env, start_response)
        except Exception as e:
            return self._json(start_response, 500, {"ok": False, "error": f"auth_err: {e}"})
        return self.inner(env, start_response)
# ---- envolver una sola vez (outermost) ----
try:
    _P12_AUTH_WRAPPED
except NameError:
    try:
        app = _AuthEndpoints(app)
    except Exception:
        pass
    _P12_AUTH_WRAPPED = True

# ================== /APPEND-ONLY AUTH ==================
"""
    changed = True

if not changed:
    print("OK: _AuthEndpoints ya presente"); sys.exit(0)

bak = W.with_suffix(".py.auth_patch.bak")
if not bak.exists():
    shutil.copyfile(W, bak)

W.write_text(s, encoding="utf-8")
py_compile.compile(str(W), doraise=True)
print("patched: auth endpoints + compile OK; backup:", bak)
