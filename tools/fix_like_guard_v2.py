#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile

W = pathlib.Path("wsgiapp/__init__.py")
s = W.read_text(encoding="utf-8")
orig = s
changed = False

# --- A) eliminar cualquier versión previa rota del guard ---
# desde el marcador hasta el final del bloque del try/except del envoltorio
pat_guard = re.compile(
    r'\n# === APPEND-ONLY: _LikesGuardSafeTxn.*?^try:\s*\n\s*_LIKES_GUARD_SAFETXN.*?= True\s*$',
    re.S | re.M
)
s, n1 = pat_guard.subn('\n', s)
if n1:
    changed = True

# Además, por si quedó una variante con secuencias escapadas \"\"\" y \n dentro:
pat_escaped = re.compile(
    r'\n# === APPEND-ONLY: _LikesGuardSafeTxn.*?_LIKES_GUARD_SAFETXN\s*=\s*True.*?(?:\n|$)',
    re.S
)
s, n2 = pat_escaped.subn('\n', s)
if n2:
    changed = True

# --- B) asegurar import y alias T = _text (una sola vez) ---
if not re.search(r'(?m)^\s*from\s+sqlalchemy\s+import\s+text\s+as\s+_text\s*$', s):
    # insertamos tras shebang/docstring si existe
    insert_at = 0
    if s.startswith("#!"):
        insert_at = s.find("\n") + 1
    mdoc = re.match(r'\A\s*(?P<q>["\']{3}).*?(?P=q)\s*', s, flags=re.S)
    if mdoc:
        insert_at = mdoc.end()
    s = s[:insert_at] + "\nfrom sqlalchemy import text as _text\n" + s[insert_at:]
    changed = True

if not re.search(r'(?m)^\s*T\s*=\s*_text\s*$', s):
    # ponemos el alias justo después del import
    mim = re.search(r'(?m)^\s*from\s+sqlalchemy\s+import\s+text\s+as\s+_text\s*$', s)
    if mim:
        pos = mim.end()
        s = s[:pos] + "\nT = _text\n" + s[pos:]
        changed = True

# --- C) insertar guard correcto sólo si no existe ---
if "_LIKES_GUARD_SAFETXN" not in s:
    block = '''
# === APPEND-ONLY: _LikesGuardSafeTxn (dedupe 1×persona, transacciones seguras) ===
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
        # Idempotente: tabla + índice único (o PK compuesta)
        try:
            cx.execute(T("""
CREATE TABLE IF NOT EXISTS like_log(
  note_id INTEGER NOT NULL REFERENCES note(id) ON DELETE CASCADE,
  fingerprint VARCHAR(128) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (note_id, fingerprint)
)
"""))
        except Exception:
            pass
        try:
            cx.execute(T("""
CREATE UNIQUE INDEX IF NOT EXISTS uq_like_note_fp
ON like_log(note_id, fingerprint)
"""))
        except Exception:
            pass

    def _handle(self, env, start_response, note_id):
        try:
            from wsgiapp.__init__ import _engine
            eng = _engine()
            fp = self._fp(env)
            with eng.begin() as cx:
                self._bootstrap_like(cx)
                # INSERT que NO lanza excepción si ya existe => no aborta txn
                res = cx.execute(T(
                    "INSERT INTO like_log(note_id, fingerprint) VALUES (:id,:fp) "
                    "ON CONFLICT (note_id, fingerprint) DO NOTHING"
                ), {"id": note_id, "fp": fp})
                inserted = bool(getattr(res, "rowcount", 0))
                if inserted:
                    cx.execute(T(
                        "UPDATE note SET likes = COALESCE(likes,0)+1 WHERE id=:id"
                    ), {"id": note_id})
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

# --- envolver outermost una sola vez ---
try:
    _LIKES_GUARD_SAFETXN
except NameError:
    try:
        app = _LikesGuardSafeTxn(app)
    except Exception:
        pass
    _LIKES_GUARD_SAFETXN = True
'''.lstrip("\n")
    s = (s if s.endswith("\n") else s + "\n") + block
    changed = True

if not changed:
    print("OK: nada para cambiar")
else:
    bak = W.with_suffix(".py.likes_guard_v2.bak")
    if not bak.exists():
        shutil.copyfile(W, bak)
    W.write_text(s, encoding="utf-8")
    print(f"patched: likes guard v2 (backup: {bak.name})")

# Gate de compilación
py_compile.compile(str(W), doraise=True)
print("✓ py_compile OK")
