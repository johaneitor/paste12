#!/usr/bin/env python3
import pathlib, re, sys, shutil, py_compile

W = pathlib.Path("wsgiapp/__init__.py")
s = W.read_text(encoding="utf-8")
raw = s
changed = False

if "class _AuthRoutes" not in s:
    block = r'''
# === APPEND-ONLY: AUTH MIN (usuario+pass+3 preguntas) ===
import os as _os, json as _json, hmac as _hmac, hashlib as _hashlib, secrets as _secrets, time as _time
from urllib.parse import parse_qs as _parse_qs
from sqlalchemy import text as _text

def _auth_now_utc():
    from datetime import datetime, timezone
    return datetime.now(timezone.utc)

def _auth_pbkdf2_hash(secret: str, salt_hex: str|None=None, iters: int=130_000):
    if not salt_hex:
        salt_hex = _secrets.token_hex(16)
    dk = _hashlib.pbkdf2_hmac("sha256", secret.encode("utf-8"), bytes.fromhex(salt_hex), iters)
    return salt_hex, dk.hex()

def _auth_ct_equal(a: str, b: str) -> bool:
    try:
        return _hmac.compare_digest(a, b)
    except Exception:
        # fallback
        if len(a) != len(b): return False
        res = 0
        for x,y in zip(a.encode(), b.encode()): res |= (x ^ y)
        return res == 0

def _auth_parse_body(environ):
    try:
        ct = (environ.get("CONTENT_TYPE") or "").split(";")[0].strip().lower()
        ln = int(environ.get("CONTENT_LENGTH") or "0")
        body = (environ["wsgi.input"].read(ln) if ln>0 else b"") or b""
        if ct == "application/json":
            return True, _json.loads(body.decode("utf-8") or "{}")
        elif ct == "application/x-www-form-urlencoded":
            d = {k: v[0] if isinstance(v, list) and v else "" for k,v in _parse_qs(body.decode("utf-8"), keep_blank_values=True).items()}
            return False, d
        else:
            # intenta JSON de todos modos
            try:
                return True, _json.loads(body.decode("utf-8") or "{}")
            except Exception:
                return False, {}
    except Exception:
        return False, {}

def _auth_header_json(code: int, payload: dict):
    body = _json.dumps(payload, default=str).encode("utf-8")
    return f"{code} OK", [("Content-Type","application/json; charset=utf-8"),
                          ("Content-Length", str(len(body))),
                          ("Cache-Control","no-store")], [body]

def _auth_get_bearer(environ):
    h = environ.get("HTTP_AUTHORIZATION") or ""
    if h.lower().startswith("bearer "):
        return h.split(" ",1)[1].strip()
    return ""

def _auth_bootstrap(cx):
    # users
    cx.execute(_text("""
        CREATE TABLE IF NOT EXISTS users(
          id SERIAL PRIMARY KEY,
          username VARCHAR(32) UNIQUE NOT NULL,
          pass_salt TEXT NOT NULL,
          pass_hash TEXT NOT NULL,
          a1_salt TEXT NOT NULL,
          a1_hash TEXT NOT NULL,
          a2_salt TEXT NOT NULL,
          a2_hash TEXT NOT NULL,
          a3_salt TEXT NOT NULL,
          a3_hash TEXT NOT NULL,
          created_at TIMESTAMPTZ DEFAULT NOW()
        )
    """))
    # sessions
    cx.execute(_text("""
        CREATE TABLE IF NOT EXISTS sessions(
          token VARCHAR(64) PRIMARY KEY,
          user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          created_at TIMESTAMPTZ DEFAULT NOW(),
          expires_at TIMESTAMPTZ
        )
    """))
    try:
        cx.execute(_text("CREATE UNIQUE INDEX IF NOT EXISTS uq_users_username ON users(username)"))
    except Exception:
        pass

def _auth_find_user(cx, username: str):
    return cx.execute(_text("SELECT * FROM users WHERE username=:u"), {"u": username}).mappings().first()

def _auth_insert_session(cx, user_id: int, days: int):
    tok = _secrets.token_hex(32)
    cx.execute(_text("INSERT INTO sessions(token, user_id, expires_at) VALUES (:t,:u, NOW() + (:d || ' days')::interval)"),
               {"t": tok, "u": user_id, "d": days})
    return tok

def _auth_get_user_by_token(cx, tok: str):
    if not tok: return None
    return cx.execute(_text("SELECT u.* FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token=:t AND (s.expires_at IS NULL OR s.expires_at>NOW())"),
                      {"t": tok}).mappings().first()

def _auth_delete_token(cx, tok: str):
    if tok:
        cx.execute(_text("DELETE FROM sessions WHERE token=:t"), {"t": tok})

class _AuthRoutes:
    def __init__(self, inner):
        self.inner = inner

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        method = (environ.get("REQUEST_METHOD") or "GET").upper()

        if not path.startswith("/api/auth/"):
            # no es ruta de auth → pasa
            return self.inner(environ, start_response)

        # Todas las rutas de auth responden JSON
        try:
            from wsgiapp.__init__ import _engine  # reutiliza la misma fábrica
            with _engine().begin() as cx:
                _auth_bootstrap(cx)

            # -------- REGISTER --------
            if method == "POST" and path == "/api/auth/register":
                is_json, data = _auth_parse_body(environ)
                username = (data.get("username") or "").strip()
                password = (data.get("password") or "")
                a1 = (data.get("a1") or "")
                a2 = (data.get("a2") or "")
                a3 = (data.get("a3") or "")
                # validaciones básicas
                import re as _re
                if not _re.match(r"^[A-Za-z0-9_]{3,20}$", username):
                    status, headers, body = _auth_header_json(400, {"ok": False, "error": "bad_username"})
                    start_response(status, headers); return body
                if not (8 <= len(password) <= 128):
                    status, headers, body = _auth_header_json(400, {"ok": False, "error": "weak_password"})
                    start_response(status, headers); return body
                if not (a1 and a2 and a3):
                    status, headers, body = _auth_header_json(400, {"ok": False, "error": "answers_required"})
                    start_response(status, headers); return body

                with _engine().begin() as cx:
                    if _auth_find_user(cx, username):
                        status, headers, body = _auth_header_json(409, {"ok": False, "error": "username_taken"})
                        start_response(status, headers); return body
                    ps, ph = _auth_pbkdf2_hash(password)
                    s1, h1 = _auth_pbkdf2_hash(a1)
                    s2, h2 = _auth_pbkdf2_hash(a2)
                    s3, h3 = _auth_pbkdf2_hash(a3)
                    cx.execute(_text("""INSERT INTO users(username,pass_salt,pass_hash,
                                                 a1_salt,a1_hash,a2_salt,a2_hash,a3_salt,a3_hash)
                                        VALUES(:u,:ps,:ph,:s1,:h1,:s2,:h2,:s3,:h3)"""),
                              {"u":username,"ps":ps,"ph":ph,"s1":s1,"h1":h1,"s2":s2,"h2":h2,"s3":s3,"h3":h3})
                status, headers, body = _auth_header_json(201, {"ok": True})
                start_response(status, headers); return body

            # -------- LOGIN --------
            if method == "POST" and path == "/api/auth/login":
                is_json, data = _auth_parse_body(environ)
                username = (data.get("username") or "").strip()
                password = (data.get("password") or "")
                days = int((_os.getenv("AUTH_SESSION_DAYS") or "30") or "30")
                with _engine().begin() as cx:
                    u = _auth_find_user(cx, username)
                    if not u:
                        status, headers, body = _auth_header_json(403, {"ok": False, "error": "invalid_auth"})
                        start_response(status, headers); return body
                    salt = u["pass_salt"]; want = u["pass_hash"]
                    _s, got = _auth_pbkdf2_hash(password, salt)
                    if not _auth_ct_equal(got, want):
                        status, headers, body = _auth_header_json(403, {"ok": False, "error": "invalid_auth"})
                        start_response(status, headers); return body
                    tok = _auth_insert_session(cx, u["id"], days)
                status, headers, body = _auth_header_json(200, {"ok": True, "token": tok, "user": {"id": u["id"], "username": u["username"]}})
                start_response(status, headers); return body

            # -------- LOGOUT --------
            if method == "POST" and path == "/api/auth/logout":
                tok = _auth_get_bearer(environ)
                with _engine().begin() as cx:
                    _auth_delete_token(cx, tok)
                status, headers, body = _auth_header_json(200, {"ok": True})
                start_response(status, headers); return body

            # -------- ME --------
            if method == "GET" and path == "/api/auth/me":
                tok = _auth_get_bearer(environ)
                with _engine().begin() as cx:
                    u = _auth_get_user_by_token(cx, tok)
                if not u:
                    status, headers, body = _auth_header_json(403, {"ok": False, "error": "invalid_auth"})
                else:
                    status, headers, body = _auth_header_json(200, {"ok": True, "user": {"id": u["id"], "username": u["username"]}})
                start_response(status, headers); return body

            # -------- RECOVERY (init) --------
            if method == "POST" and path == "/api/auth/recover-init":
                is_json, data = _auth_parse_body(environ)
                username = (data.get("username") or "").strip()
                with _engine().begin() as cx:
                    u = _auth_find_user(cx, username)
                # Para no filtrar existencia: responder 200 genérico
                status, headers, body = _auth_header_json(200, {"ok": True, "questions": [
                    {"id":1,"text":"¿Tu número favorito?"},
                    {"id":2,"text":"¿Nombre de tu primera mascota?"},
                    {"id":3,"text":"¿Primaria donde estudiaste?"}
                ]})
                start_response(status, headers); return body

            # -------- RECOVERY (complete) --------
            if method == "POST" and path == "/api/auth/recover-complete":
                is_json, data = _auth_parse_body(environ)
                username = (data.get("username") or "").strip()
                a1 = (data.get("a1") or ""); a2 = (data.get("a2") or ""); a3 = (data.get("a3") or "")
                newp = (data.get("new_password") or "")
                if not (8 <= len(newp) <= 128):
                    status, headers, body = _auth_header_json(400, {"ok": False, "error": "weak_password"})
                    start_response(status, headers); return body
                with _engine().begin() as cx:
                    u = _auth_find_user(cx, username)
                    if not u:
                        status, headers, body = _auth_header_json(403, {"ok": False, "error": "invalid_recovery"})
                        start_response(status, headers); return body
                    ok1 = _auth_ct_equal(_auth_pbkdf2_hash(a1, u["a1_salt"])[1], u["a1_hash"])
                    ok2 = _auth_ct_equal(_auth_pbkdf2_hash(a2, u["a2_salt"])[1], u["a2_hash"])
                    ok3 = _auth_ct_equal(_auth_pbkdf2_hash(a3, u["a3_salt"])[1], u["a3_hash"])
                    if not (ok1 and ok2 and ok3):
                        status, headers, body = _auth_header_json(403, {"ok": False, "error": "invalid_recovery"})
                        start_response(status, headers); return body
                    ps, ph = _auth_pbkdf2_hash(newp)
                    cx.execute(_text("UPDATE users SET pass_salt=:s, pass_hash=:h WHERE id=:id"),
                               {"s": ps, "h": ph, "id": u["id"]})
                    cx.execute(_text("DELETE FROM sessions WHERE user_id=:id"), {"id": u["id"]})
                status, headers, body = _auth_header_json(200, {"ok": True})
                start_response(status, headers); return body

            # Si ninguna de auth matchea, 404 de auth (evitamos colisionar con otras rutas)
            status, headers, body = _auth_header_json(404, {"ok": False, "error": "auth_not_found"})
            start_response(status, headers); return body

        except Exception as e:
            status, headers, body = _auth_header_json(500, {"ok": False, "error": str(e)})
            start_response(status, headers); return body

# Envolver una sola vez (outermost posible)
try:
    _AUTH_ROUTES_WRAPPED
except NameError:
    try:
        app = _AuthRoutes(app)
    except Exception:
        pass
    _AUTH_ROUTES_WRAPPED = True
'''
    if not s.endswith("\n"):
        s += "\n"
    s += "\n" + block.lstrip("\n")
    changed = True

if not changed:
    print("OK: _AuthRoutes ya estaba presente")
else:
    bak = W.with_suffix(".py.auth_min.bak")
    if not bak.exists():
        shutil.copyfile(W, bak)
    W.write_text(s, encoding="utf-8")
    print("patched: _AuthRoutes (auth mínimo)")

# compile gate
py_compile.compile(str(W), doraise=True)
print("✓ py_compile OK")
