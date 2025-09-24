#!/usr/bin/env bash
set -euo pipefail

BASE_REMOTE="${1:-origin}"
BRANCH="${2:-main}"

echo "== Backup y reset a remoto =="
CURSHA="$(git rev-parse HEAD | head -c40)"
BK="backup-$(date +%Y%m%d-%H%M%S)-$CURSHA"
git branch "$BK" >/dev/null 2>&1 || true
git stash push -u -m "pre-repair $BK" >/dev/null 2>&1 || true
git fetch --all --prune
git checkout -B "$BRANCH" "$BASE_REMOTE/$BRANCH"
git reset --hard "$BASE_REMOTE/$BRANCH"

echo "== Reaplicar parches funcionales (sin workflows) =="

# 1) Patch likes dedupe (append-only, reversible por flag)
cat > tools/patch_likes_on_conflict.py <<'PY'
#!/usr/bin/env python3
import pathlib
P = pathlib.Path("wsgiapp/__init__.py")
s = P.read_text(encoding="utf-8")
if "class _LikesGuardOC" in s:
    print("ya estaba inyectado")
else:
    s += r"""

# === APPEND-ONLY: Guard de likes 1×persona con ON CONFLICT (flag ENABLE_LIKES_DEDUPE) ===
class _LikesGuardOC:
    def __init__(self, inner):
        self.inner = inner
    def _fp(self, environ):
        import hashlib
        fp = (environ.get("HTTP_X_FP") or "").strip()
        if fp: return fp[:128]
        parts = [
            (environ.get("HTTP_X_FORWARDED_FOR","").split(",")[0] or "").strip(),
            (environ.get("REMOTE_ADDR","") or "").strip(),
            (environ.get("HTTP_USER_AGENT","") or "").strip(),
        ]
        return hashlib.sha256("|".join(parts).encode("utf-8","ignore")).hexdigest()
    def _json(self, start_response, code, payload):
        import json
        body = json.dumps(payload, default=str).encode("utf-8")
        start_response(f"{code} OK", [
            ("Content-Type","application/json; charset=utf-8"),
            ("Content-Length", str(len(body))),
            ("X-WSGI-Bridge","1"),
        ])
        return [body]
    def _bootstrap_like_log(self, cx):
        from sqlalchemy import text as T
        # Tabla (Postgres) y fallback SQLite. Índice único necesario para dedupe.
        try:
            cx.execute(T("""
                CREATE TABLE IF NOT EXISTS like_log(
                    id SERIAL PRIMARY KEY,
                    note_id INTEGER NOT NULL REFERENCES note(id) ON DELETE CASCADE,
                    fingerprint VARCHAR(128) NOT NULL,
                    created_at TIMESTAMPTZ DEFAULT NOW()
                )"""))
        except Exception:
            try:
                cx.execute(T("""
                    CREATE TABLE IF NOT EXISTS like_log(
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        note_id INTEGER NOT NULL,
                        fingerprint VARCHAR(128) NOT NULL,
                        created_at TEXT DEFAULT CURRENT_TIMESTAMP
                    )"""))
            except Exception:
                pass
        try:
            cx.execute(T("""CREATE UNIQUE INDEX IF NOT EXISTS uq_like_note_fp
                            ON like_log(note_id, fingerprint)"""))
        except Exception:
            pass
    def _handle_like(self, environ, start_response, note_id):
        import os
        from sqlalchemy import text as T
        flag = (environ.get("ENABLE_LIKES_DEDUPE") or os.getenv("ENABLE_LIKES_DEDUPE","1")).strip().lower()
        if flag not in ("1","true","yes","on"):
            return self.inner(environ, start_response)
        try:
            from wsgiapp.__init__ import _engine
            eng = _engine()
            fp = self._fp(environ)
            with eng.begin() as cx:
                self._bootstrap_like_log(cx)
                inserted = False
                try:
                    r = cx.execute(T("""
                        INSERT INTO like_log(note_id, fingerprint)
                        VALUES (:id,:fp)
                        ON CONFLICT (note_id, fingerprint) DO NOTHING
                    """), {"id": note_id, "fp": fp})
                    if r.rowcount and r.rowcount > 0:
                        inserted = True
                    else:
                        got = cx.execute(T(
                          "SELECT 1 FROM like_log WHERE note_id=:id AND fingerprint=:fp LIMIT 1"
                        ), {"id": note_id, "fp": fp}).first()
                        inserted = (got is None)
                except Exception:
                    try:
                        cx.execute(T(
                          "INSERT INTO like_log(note_id, fingerprint) VALUES (:id,:fp)"
                        ), {"id": note_id, "fp": fp})
                        inserted = True
                    except Exception:
                        inserted = False
                if inserted:
                    cx.execute(T(
                      "UPDATE note SET likes = COALESCE(likes,0)+1 WHERE id=:id"
                    ), {"id": note_id})
                row = cx.execute(T(
                  "SELECT id, COALESCE(likes,0) AS likes, COALESCE(views,0) AS views, COALESCE(reports,0) AS reports FROM note WHERE id=:id"
                ), {"id": note_id}).mappings().first()
                if not row:
                    return self._json(start_response, 404, {"ok": False, "error": "not_found"})
                return self._json(start_response, 200, {
                    "ok": True,
                    "id": row["id"], "likes": row["likes"], "views": row["views"],
                    "reports": row["reports"], "deduped": not inserted
                })
        except Exception as e:
            return self._json(start_response, 500, {"ok": False, "error": str(e)})
    def __call__(self, environ, start_response):
        try:
            path = (environ.get("PATH_INFO","") or "")
            method = (environ.get("REQUEST_METHOD","GET") or "GET").upper()
            if method=="POST" and path.startswith("/api/notes/") and path.endswith("/like"):
                seg = path[len("/api/notes/"):-len("/like")]
                try: nid = int(seg.strip("/"))
                except Exception: nid = None
                if nid: return self._handle_like(environ, start_response, nid)
        except Exception:
            pass
        return self.inner(environ, start_response)

try:
    _LIKES_OC_WRAPPED
except NameError:
    try:
        app = _LikesGuardOC(app)
    except Exception:
        pass
    _LIKES_OC_WRAPPED = True
"""
    P.write_text(s, encoding="utf-8")
    print("patched: _LikesGuardOC")
PY
python tools/patch_likes_on_conflict.py

# 2) Brand/Tagline en index pastel (idempotente)
cat > tools/ensure_brand_title.py <<'PY'
#!/usr/bin/env python3
import re, sys, pathlib, shutil
IDX = pathlib.Path("backend/static/index.html")
if not IDX.exists():
    print("ERROR: backend/static/index.html no existe"); sys.exit(2)
s = IDX.read_text(encoding="utf-8"); bak = IDX.with_suffix(".html.bak"); changed=False
if not re.search(r"<title>\s*Paste12\s*</title>", s, flags=re.I):
    s = re.sub(r"<title>.*?</title>", "<title>Paste12</title>", s, 1, flags=re.S|re.I) if re.search(r"<title>.*?</title>", s, flags=re.S|re.I) else re.sub(r"</head>", "  <title>Paste12</title>\n</head>", s, 1, flags=re.I); changed=True
if not re.search(r'<h1[^>]*class="[^"]*\bbrand\b[^"]*"[^>]*>\s*Paste12\s*</h1>', s, flags=re.I):
    def _fix(h):
        h = re.sub(r'class="([^"]*)"', lambda m: f'class="{m.group(1)} brand"', h, 1, flags=re.I) if re.search(r'class="', h, flags=re.I) else h.replace("<h1", '<h1 class="brand"')
        return re.sub(r">(.*?)</h1>", ">Paste12</h1>", h, flags=re.S)
    s2, n = re.subn(r"(<header\b[^>]*>.*?)(<h1\b[^>]*>.*?</h1>)(.*?</header>)", lambda m: m.group(1)+_fix(m.group(2))+m.group(3), s, flags=re.S|re.I)
    if n: s, changed = s2, True
    else:
        s2, n = re.subn(r"(<header\b[^>]*>)", r'\1\n  <h1 class="brand">Paste12</h1>', s, flags=re.I)
        if n: s, changed = s2, True
        else:
            s2, n = re.subn(r"(<body\b[^>]*>)", r'\1\n<header><h1 class="brand">Paste12</h1></header>', s, flags=re.I)
            if n: s, changed = s2, True
if not re.search(r'<div\s+id="tagline"\b', s, flags=re.I):
    s2, n = re.subn(r'(<header\b[^>]*>.*?<h1\b[^>]*class="[^"]*\bbrand\b[^"]*"[^>]*>.*?</h1>)', r'\1\n  <div id="tagline">Reta a un amigo · Dime un secreto · Confiesa algo</div>', s, flags=re.S|re.I)
    if n: s, changed = s2, True
if changed:
    if not bak.exists(): shutil.copyfile(IDX, bak)
    IDX.write_text(s, encoding="utf-8"); print("patched: title/brand/tagline")
else:
    print("OK: ya estaba con title/brand/tagline")
PY
python tools/ensure_brand_title.py

echo "== Commit sólo cambios funcionales =="
git add wsgiapp/__init__.py backend/static/index.html tools/patch_likes_on_conflict.py tools/ensure_brand_title.py
git commit -m "feat: likes 1x persona (ON CONFLICT) + brand/tagline (sin workflows)"
git push "$BASE_REMOTE" "$BRANCH"
echo "Listo. Siguiente paso: disparar deploy Render."
