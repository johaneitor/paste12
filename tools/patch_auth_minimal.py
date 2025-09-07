#!/usr/bin/env python3
import pathlib, re, sys, shutil, py_compile

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ wsgiapp/__init__.py no existe"); sys.exit(2)

raw = W.read_text(encoding="utf-8")
s = raw
changed = False

if "class _AuthLayer" not in s:
    block = r'''
# === APPEND-ONLY: Auth mínima (usuario/contraseña + 3 respuestas) ===
import os as _os, json as _json, base64 as _b64, hmac as _hmac, hashlib as _hashlib, time as _time, secrets as _secrets, re as _re
from typing import Callable as _Callable
import importlib as _importlib

def _b64u(b: bytes) -> str:
    return _b64.urlsafe_b64encode(b).decode().rstrip("=")
def _b64u_dec(s: str) -> bytes:
    p = "="*((4 - len(s)%4)%4)
    return _b64.urlsafe_b64decode(s + p)

def _auth_secret():
    return (_os.getenv("AUTH_SECRET") or "change-me-auth-secret").encode()
def _auth_pepper():
    return (_os.getenv("AUTH_PEPPER") or "change-me-auth-pepper")

def _now_ts():
    return int(_time.time())

def _fp_from_env(environ):
    fp = (environ.get("HTTP_X_FP") or "").strip()
    if fp: return fp[:128]
    ip = (environ.get("REMOTE_ADDR","") or "").strip()
    ua = (environ.get("HTTP_USER_AGENT","") or "").strip()
    raw = f"{ip}|{ua}".encode("utf-8","ignore")
    return _hashlib.sha256(raw).hexdigest()

def _hash_scrypt(secret: str, salt: bytes|None=None, pepper: str="") -> tuple[str,str]:
    if salt is None: salt = _secrets.token_bytes(16)
    data = (secret + "|" + pepper).encode("utf-8")
    key = _hashlib.scrypt(data, salt=salt, n=2**14, r=8, p=1, dklen=32)
    return _b64u(salt), _b64u(key)

def _verify_scrypt(secret: str, salt_b64: str, key_b64: str, pepper: str="") -> bool:
    try:
        salt = _b64u_dec(salt_b64); want = _b64u_dec(key_b64)
        data = (secret + "|" + pepper).encode("utf-8")
        got = _hashlib.scrypt(data, salt=salt, n=2**14, r=8, p=1, dklen=32)
        return _hmac.compare_digest(got, want)
    except Exception:
        return False

def _sign_session(payload: dict) -> str:
    body = _b64u(_json.dumps(payload, separators=(",",":")).encode())
    sig  = _b64u(_hmac.new(_auth_secret(), body.encode(), _hashlib.sha256).digest())
    return body + "." + sig

def _verify_session(tok: str) -> dict|None:
    try:
        body, sig = tok.split(".", 1)
        sig2 = _b64u(_hmac.new(_auth_secret(), body.encode(), _hashlib.sha256).digest())
        if not _hmac.compare_digest(sig, sig2): return None
        payload = _json.loads(_b64u_dec(body))
        if int(payload.get("exp",0)) < _now_ts(): return None
        return payload
    except Exception:
        return None

def _cookie(name, val, maxage=None):
    base = f"{name}={val}; Path=/; HttpOnly; SameSite=Lax"
    if maxage is not None: base += f"; Max-Age={maxage}"
    base += "; Secure"
    return ("Set-Cookie", base)

def _read_json_body(environ) -> dict:
    try:
        l = int(environ.get("CONTENT_LENGTH") or "0")
    except Exception:
        l = 0
    body = environ["wsgi.input"].read(l) if l>0 else b""
    try:
        return _json.loads(body.decode("utf-8"))
    except Exception:
        return {}

def _json_resp(start, code, payload):
    data = _json.dumps(payload, default=str).encode("utf-8")
    start(f"{code} OK", [("Content-Type","application/json; charset=utf-8"),
                         ("Content-Length", str(len(data))),
                         ("Cache-Control","no-store, no-cache, must-revalidate, max-age=0"),
                         ("X-WSGI-Bridge","1")])
    return [data]

def _rate_hit(cx, fp, action, limit, window_sec) -> bool:
    from sqlalchemy import text as _text
    cx.execute(_text("""
        CREATE TABLE IF NOT EXISTS auth_rate(
          fp VARCHAR(128) NOT NULL,
          action VARCHAR(32) NOT NULL,
          ts TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
    """))
    cx.execute(_text("DELETE FROM auth_rate WHERE ts < NOW() - (:w || ' seconds')::interval"), {"w": window_sec})
    cx.execute(_text("INSERT INTO auth_rate(fp, action) VALUES (:fp, :act)"), {"fp": fp, "act": action})
    cnt = cx.execute(_text("""
        SELECT COUNT(*) FROM auth_rate
        WHERE fp=:fp AND action=:act AND ts > NOW() - (:w || ' seconds')::interval
    """), {"fp": fp, "act": action, "w": window_sec}).scalar_one()
    return int(cnt) <= int(limit)

def _ensure_auth_schema(cx):
    from sqlalchemy import text as _text
    cx.execute(_text("""
    CREATE TABLE IF NOT EXISTS account(
      id SERIAL PRIMARY KEY,
      username VARCHAR(50) UNIQUE NOT NULL,
      pw_salt TEXT NOT NULL,
      pw_hash TEXT NOT NULL,
      created_at TIMESTAMPTZ DEFAULT NOW()
    )"""))
    cx.execute(_text("""
    CREATE TABLE IF NOT EXISTS account_recovery(
      user_id INTEGER PRIMARY KEY REFERENCES account(id) ON DELETE CASCADE,
      a1_salt TEXT NOT NULL, a1_hash TEXT NOT NULL,
      a2_salt TEXT NOT NULL, a2_hash TEXT NOT NULL,
      a3_salt TEXT NOT NULL, a3_hash TEXT NOT NULL,
      created_at TIMESTAMPTZ DEFAULT NOW()
    )"""))
    try:
        cx.execute(_text("ALTER TABLE note ADD COLUMN IF NOT EXISTS author_id INTEGER REFERENCES account(id)"))
    except Exception:
        pass
    try:
        cx.execute(_text("CREATE INDEX IF NOT EXISTS ix_note_author ON note(author_id, timestamp DESC)"))
    except Exception:
        pass

class _AuthLayer:
    def __init__(self, inner: _Callable):
        self.inner = inner

    def _eng(self):
        try:
            mod = _importlib.import_module("wsgiapp.__init__")
            return mod._engine()
        except Exception:
            return globals()["_engine"]()

    def _with_capture(self, environ, start_response):
        out = {"status": None, "headers": [], "body": b""}
        def sr(status, headers, exc_info=None):
            out["status"] = status; out["headers"] = headers; return None
        app_iter = self.inner(environ, sr)
        try:
            for chunk in app_iter:
                out["body"] += chunk
        finally:
            if hasattr(app_iter, "close"):
                try: app_iter.close()
                except Exception: pass
        return out

    def _me_from_cookie(self, environ):
        cookie = environ.get("HTTP_COOKIE","")
        tok = None
        for part in cookie.split(";"):
            kv = part.strip().split("=",1)
            if len(kv)==2 and kv[0]=="sess":
                tok = kv[1]; break
        if not tok: return None
        payload = _verify_session(tok)
        if not payload: return None
        return {"uid": int(payload.get("uid",0)), "exp": int(payload.get("exp",0))}

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO","") or "")
        method = (environ.get("REQUEST_METHOD","GET") or "GET").upper()

        # ---- endpoints auth ----
        if method=="POST" and path=="/api/register":
            data = _read_json_body(environ)
            u = (data.get("username") or "").strip()
            p = (data.get("password") or "")
            a1 = (data.get("a1") or ""); a2=(data.get("a2") or ""); a3=(data.get("a3") or "")
            if not (3 <= len(u) <= 30) or not _re.match(r"^[a-zA-Z0-9_]+$", u):
                return _json_resp(start_response, 400, {"ok": False, "error":"bad_username"})
            if len(p) < 8:
                return _json_resp(start_response, 400, {"ok": False, "error":"weak_password"})
            if not (a1 and a2 and a3):
                return _json_resp(start_response, 400, {"ok": False, "error":"answers_required"})
            fp = _fp_from_env(environ)
            from sqlalchemy import text as _text
            try:
                with self._eng().begin() as cx:
                    _ensure_auth_schema(cx)
                    if not _rate_hit(cx, fp, "register", limit=5, window_sec=3600):
                        return _json_resp(start_response, 429, {"ok": False, "error":"rate_limited"})
                    pw_s, pw_h = _hash_scrypt(p, pepper=_auth_pepper())
                    a1s,a1h = _hash_scrypt(a1, pepper=_auth_pepper())
                    a2s,a2h = _hash_scrypt(a2, pepper=_auth_pepper())
                    a3s,a3h = _hash_scrypt(a3, pepper=_auth_pepper())
                    row = cx.execute(_text("INSERT INTO account(username,pw_salt,pw_hash) VALUES(:u,:s,:h) RETURNING id"),
                                     {"u":u,"s":pw_s,"h":pw_h}).first()
                    uid = int(row[0])
                    cx.execute(_text("""
                        INSERT INTO account_recovery(user_id,a1_salt,a1_hash,a2_salt,a2_hash,a3_salt,a3_hash)
                        VALUES(:uid,:s1,:h1,:s2,:h2,:s3,:h3)
                    """), {"uid":uid,"s1":a1s,"h1":a1h,"s2":a2s,"h2":a2h,"s3":a3s,"h3":a3h})
                return _json_resp(start_response, 201, {"ok": True, "user":{"id":uid,"username":u}})
            except Exception:
                return _json_resp(start_response, 400, {"ok": False, "error": "register_failed"})

        if method=="POST" and path=="/api/login":
            data = _read_json_body(environ)
            u = (data.get("username") or "").strip()
            p = (data.get("password") or "")
            from sqlalchemy import text as _text
            fp = _fp_from_env(environ)
            try:
                with self._eng().begin() as cx:
                    _ensure_auth_schema(cx)
                    if not _rate_hit(cx, fp, "login", limit=30, window_sec=600):
                        return _json_resp(start_response, 429, {"ok": False, "error":"rate_limited"})
                    row = cx.execute(_text("SELECT id, pw_salt, pw_hash FROM account WHERE username=:u"), {"u":u}).first()
                    if not row or not _verify_scrypt(p, row[1], row[2], pepper=_auth_pepper()):
                        return _json_resp(start_response, 401, {"ok": False, "error":"invalid_credentials"})
                    uid = int(row[0])
                tok = _sign_session({"uid":uid, "exp": _now_ts()+7*24*3600})
                headers = [_cookie("sess", tok, 7*24*3600)]
                def sr(s,h,exc=None):
                    return start_response(s, h + headers, exc)
                return _json_resp(sr, 200, {"ok":True, "user":{"id":uid, "username":u}})
            except Exception:
                return _json_resp(start_response, 500, {"ok": False, "error": "login_failed"})

        if method=="POST" and path=="/api/logout":
            headers = [_cookie("sess", "x", 0)]
            def sr(s,h,exc=None): return start_response(s, h+headers, exc)
            return _json_resp(sr, 200, {"ok": True})

        if method=="GET" and path=="/api/me":
            me = self._me_from_cookie(environ)
            if not me: return _json_resp(start_response, 401, {"ok": False, "error":"unauth"})
            from sqlalchemy import text as _text
            with self._eng().begin() as cx:
                row = cx.execute(_text("SELECT id,username FROM account WHERE id=:id"), {"id": me["uid"]}).first()
            if not row: return _json_resp(start_response, 401, {"ok": False, "error":"unauth"})
            return _json_resp(start_response, 200, {"ok": True, "user":{"id":int(row[0]), "username":row[1]}})

        if method=="POST" and path=="/api/recover":
            data = _read_json_body(environ)
            u = (data.get("username") or "").strip()
            a1=(data.get("a1") or ""); a2=(data.get("a2") or ""); a3=(data.get("a3") or "")
            newp=(data.get("new_password") or "")
            if len(newp) < 8:
                return _json_resp(start_response, 400, {"ok": False, "error":"weak_password"})
            from sqlalchemy import text as _text
            try:
                with self._eng().begin() as cx:
                    row = cx.execute(_text("""
                        SELECT a.id,a.username,r.a1_salt,r.a1_hash,r.a2_salt,r.a2_hash,r.a3_salt,r.a3_hash
                        FROM account a JOIN account_recovery r ON r.user_id=a.id WHERE a.username=:u
                    """), {"u":u}).first()
                    if not row: return _json_resp(start_response, 404, {"ok": False, "error":"not_found"})
                    ok1 = _verify_scrypt(a1, row[2], row[3], pepper=_auth_pepper())
                    ok2 = _verify_scrypt(a2, row[4], row[5], pepper=_auth_pepper())
                    ok3 = _verify_scrypt(a3, row[6], row[7], pepper=_auth_pepper())
                    if not (ok1 and ok2 and ok3):
                        return _json_resp(start_response, 403, {"ok": False, "error":"answers_mismatch"})
                    pw_s, pw_h = _hash_scrypt(newp, pepper=_auth_pepper())
                    cx.execute(_text("UPDATE account SET pw_salt=:s, pw_hash=:h WHERE id=:id"),
                               {"s":pw_s,"h":pw_h,"id":int(row[0])})
                return _json_resp(start_response, 200, {"ok": True})
            except Exception:
                return _json_resp(start_response, 500, {"ok": False, "error":"recover_failed"})

        if method=="GET" and path=="/api/my/notes":
            me = self._me_from_cookie(environ)
            if not me: return _json_resp(start_response, 401, {"ok": False, "error":"unauth"})
            import urllib.parse as _u
            qs = _u.parse_qs(environ.get("QUERY_STRING",""))
            try: limit = max(1, min(50, int((qs.get("limit") or ["20"])[0])))
            except: limit = 20
            from sqlalchemy import text as _text
            with self._eng().begin() as cx:
                rows = cx.execute(_text("""
                    SELECT id, text, title, url, summary, content, timestamp, expires_at,
                           COALESCE(likes,0) AS likes, COALESCE(views,0) AS views, COALESCE(reports,0) AS reports
                    FROM note
                    WHERE author_id=:uid
                    ORDER BY timestamp DESC, id DESC
                    LIMIT :lim
                """), {"uid": me["uid"], "lim": limit}).mappings().all()
            items = [dict(r) for r in rows]
            return _json_resp(start_response, 200, {"ok": True, "items": items})

        # ---- hook: asociación author_id tras crear nota ----
        if method=="POST" and path=="/api/notes":
            me = self._me_from_cookie(environ)
            cap = self._with_capture(environ, start_response)
            try:
                status_code = int((cap["status"] or "200").split(" ")[0])
            except: status_code = 200
            if me and status_code in (200,201):
                try:
                    body = _json.loads(cap["body"].decode("utf-8"))
                    nid = int(body.get("item",{}).get("id") or 0)
                    if nid:
                        from sqlalchemy import text as _text
                        with self._eng().begin() as cx:
                            cx.execute(_text("""
                                UPDATE note SET author_id=:uid
                                WHERE id=:id AND (author_id IS NULL OR author_id=0)
                            """), {"uid": me["uid"], "id": nid})
                except Exception:
                    pass
            # reenviar la respuesta original
            start_response(cap["status"], cap["headers"])
            return [cap["body"]]

        # default: passthrough
        return self.inner(environ, start_response)

# ---- envolver outermost (idempotente) ----
try:
    _AUTH_LAYER_WRAPPED
except NameError:
    try:
        app = _AuthLayer(app)
    except Exception:
        pass
    _AUTH_LAYER_WRAPPED = True
'''
    s += block
    changed = True

if not changed:
    print("OK: _AuthLayer ya presente"); sys.exit(0)

W.write_text(s, encoding="utf-8")
py_compile.compile(str(W), doraise=True)
print("patched: _AuthLayer + schema + cookie sessions (compile OK)")
