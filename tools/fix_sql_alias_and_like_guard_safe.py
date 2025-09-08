#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile

W = pathlib.Path("wsgiapp/__init__.py")
s = W.read_text(encoding="utf-8")
orig = s
changed = False

# --- A) Asegurar import del text() y alias T = _text ---
if not re.search(r'(?m)^from\s+sqlalchemy\s+import\s+text\s+as\s+_text\s*$', s):
    ins = "\nfrom sqlalchemy import text as _text\n"
    # insertar tras shebang/docstring si existieran
    pos = 0
    if s.startswith("#!"):
        pos = s.find("\n") + 1
    m = re.match(r'\A\s*(?P<q>["\']{3}).*?(?P=q)\s*', s, flags=re.S)
    if m: pos = m.end()
    s = s[:pos] + ins + s[pos:]
    changed = True
if "T = _text" not in s:
    # colócalo justo después del import _text
    m = re.search(r'(?m)^from\s+sqlalchemy\s+import\s+text\s+as\s+_text\s*$', s)
    if m:
        s = s[:m.end()] + "\nT = _text" + s[m.end():]
        changed = True

# --- B) Append-only: guard robusto de likes, una sola vez ---
if "_LIKES_GUARD_SAFETXN" not in s:
    block = r"""

# === APPEND-ONLY: _LikesGuardSafeTxn (dedupe 1×persona, sin abortar txn) ===
class _LikesGuardSafeTxn:
    def __init__(self, inner):
        self.inner = inner

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
        fp = (env.get("HTTP_X_FP") or "").strip()
        if fp:
            return fp[:128]
        ip = (env.get("HTTP_X_FORWARDED_FOR","").split(",")[0] or env.get("REMOTE_ADDR","")).strip()
        ua = (env.get("HTTP_USER_AGENT","") or "").strip()
        if ip or ua:
            import hashlib
            return hashlib.sha256(f"{ip}|{ua}".encode("utf-8","ignore")).hexdigest()
        return "anon"

    def _bootstrap_like(self, cx):
        # Tabla e índice/PK idempotentes; si ya existen, no fallan
        try:
            cx.execute(T(\"\"\"\nCREATE TABLE IF NOT EXISTS like_log(\n  note_id INTEGER NOT NULL REFERENCES note(id) ON DELETE CASCADE,\n  fingerprint VARCHAR(128) NOT NULL,\n  created_at TIMESTAMPTZ DEFAULT NOW(),\n  PRIMARY KEY (note_id, fingerprint)\n)\n\"\"\"))\n        except Exception:\n            pass\n        try:\n            cx.execute(T(\"\"\"\nCREATE UNIQUE INDEX IF NOT EXISTS uq_like_note_fp\nON like_log(note_id, fingerprint)\n\"\"\"))\n        except Exception:\n            pass

    def _handle(self, env, start_response, note_id):
        try:
            from wsgiapp.__init__ import _engine
            eng = _engine()
            fp = self._fp(env)
            with eng.begin() as cx:
                # 1) Esquema listo
                self._bootstrap_like(cx)
                # 2) INSERT sin lanzar excepción en colisión
                res = cx.execute(T(
                    "INSERT INTO like_log(note_id, fingerprint) VALUES (:id,:fp) "
                    "ON CONFLICT (note_id, fingerprint) DO NOTHING"
                ), {"id": note_id, "fp": fp})
                inserted = bool(getattr(res, "rowcount", 0))
                # 3) Sólo sumamos si realmente insertó
                if inserted:
                    cx.execute(T(
                        "UPDATE note SET likes = COALESCE(likes,0)+1 WHERE id=:id"
                    ), {"id": note_id})
                # 4) Estado actual
                row = cx.execute(T(
                    "SELECT id, COALESCE(likes,0) AS likes, COALESCE(views,0) AS views, COALESCE(reports,0) AS reports "
                    "FROM note WHERE id=:id"
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

    def __call__(self, env, start_response):
        try:
            path = (env.get("PATH_INFO") or "")
            method = (env.get("REQUEST_METHOD") or "GET").upper()
            if method == "POST" and path.startswith("/api/notes/") and path.endswith("/like"):
                seg = path[len("/api/notes/"):-len("/like")].strip("/")
                try:
                    nid = int(seg)
                except Exception:
                    nid = None
                if nid:
                    return self._handle(env, start_response, nid)
        except Exception:
            pass
        return self.inner(env, start_response)

# Envolver outermost 1 sola vez
try:
    _LIKES_GUARD_SAFETXN
except NameError:
    try:
        app = _LikesGuardSafeTxn(app)
    except Exception:
        pass
    _LIKES_GUARD_SAFETXN = True
"""
    s = (s if s.endswith("\n") else s + "\n") + block
    changed = True

if not changed:
    print("OK: alias/guard ya presentes")
else:
    bak = W.with_suffix(".py.likes_guard_safetxn.bak")
    if not bak.exists():
        shutil.copyfile(W, bak)
    W.write_text(s, encoding="utf-8")
    print(f"patched: likes safe guard (backup: {bak.name})")

# Gate de compilación
py_compile.compile(str(W), doraise=True)
print("✓ py_compile OK")
