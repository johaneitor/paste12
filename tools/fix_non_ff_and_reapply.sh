#!/usr/bin/env bash
set -euo pipefail

# 0) Guarda TODO lo que no esté commiteado (incluye archivos nuevos)
STAMP="$(date +%Y%m%d-%H%M%S)"
git stash push -u -m "pre-reapply-$STAMP" >/dev/null 2>&1 || true

# 1) Trae remoto y coloca tu main EXACTAMENTE en origin/main (estado limpio)
git fetch origin --prune
git reset --hard origin/main

# 2) Recupera sólo los scripts desde el stash (si existían) sin ensuciar árbol
if git stash list | grep -q "pre-reapply-$STAMP"; then
  git checkout stash@{0} -- tools || true
  git checkout stash@{0} -- backend/static/index.html || true
fi

# 3) Asegura que los dos parches estén presentes (si no existen, los crea)
mkdir -p tools

# ---- Likes 1×persona (append-only, reversible por flag ENABLE_LIKES_DEDUPE) ----
cat > tools/append_likes_guard_min.py <<'PY'
#!/usr/bin/env python3
import pathlib
P = pathlib.Path("wsgiapp/__init__.py")
s = P.read_text(encoding="utf-8")
if "class _LikesGuard" in s:
    print("ya estaba inyectado")
else:
    s += r"""

# === APPEND-ONLY: Guard de likes 1×persona (dedupe con log) ===
class _LikesGuard:
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
        raw = "|".join(parts).encode("utf-8","ignore")
        return hashlib.sha256(raw).hexdigest()

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
        except Exception:
            pass
        try:
            cx.execute(_text("""
                CREATE UNIQUE INDEX IF NOT EXISTS uq_like_note_fp
                ON like_log(note_id, fingerprint)
            """))
        except Exception:
            pass

    def _handle_like(self, environ, start_response, note_id):
        from sqlalchemy import text as _text
        import os
        enabled = (environ.get("ENABLE_LIKES_DEDUPE")
                   or os.getenv("ENABLE_LIKES_DEDUPE","1")).strip().lower() in ("1","true","yes","on")
        if not enabled:
            return self.inner(environ, start_response)
        try:
            from wsgiapp.__init__ import _engine
            eng = _engine()
            fp = self._fp(environ)
            with eng.begin() as cx:
                self._bootstrap_like_log(cx)
                inserted = False
                try:
                    cx.execute(_text(
                        "INSERT INTO like_log(note_id, fingerprint) VALUES (:id,:fp)"
                    ), {"id": note_id, "fp": fp})
                    inserted = True
                except Exception:
                    inserted = False
                if inserted:
                    cx.execute(_text(
                        "UPDATE note SET likes = COALESCE(likes,0)+1 WHERE id=:id"
                    ), {"id": note_id})
                row = cx.execute(_text(
                    "SELECT id, COALESCE(likes,0) AS likes, COALESCE(views,0) AS views, COALESCE(reports,0) AS reports FROM note WHERE id=:id"
                ), {"id": note_id}).mappings().first()
                if not row:
                    return self._json(start_response, 404, {"ok": False, "error": "not_found"})
                return self._json(start_response, 200, {
                    "ok": True,
                    "id": row["id"],
                    "likes": row["likes"],
                    "views": row["views"],
                    "reports": row["reports"],
                    "deduped": (not inserted),
                })
        except Exception as e:
            return self._json(start_response, 500, {"ok": False, "error": str(e)})

    def __call__(self, environ, start_response):
        try:
            path = (environ.get("PATH_INFO","") or "")
            method = (environ.get("REQUEST_METHOD","GET") or "GET").upper()
            if method == "POST" and path.startswith("/api/notes/") and path.endswith("/like"):
                seg = path[len("/api/notes/"):-len("/like")]
                try:
                    nid = int(seg.strip("/"))
                except Exception:
                    nid = None
                if nid:
                    return self._handle_like(environ, start_response, nid)
        except Exception:
            pass
        return self.inner(environ, start_response)

# Envolver app (idempotente)
try:
    app = _LikesGuard(app)
except Exception:
    pass
"""
    P.write_text(s, encoding="utf-8")
    print("patched: _LikesGuard append-only aplicado")
PY
chmod +x tools/append_likes_guard_min.py

# ---- Marca UI (title + h1.brand + tagline), idempotente ----
cat > tools/ensure_brand_title.py <<'PY'
#!/usr/bin/env python3
import re, sys, pathlib, shutil
IDX = pathlib.Path("backend/static/index.html")
if not IDX.exists():
    print("ERROR: backend/static/index.html no existe"); sys.exit(2)
orig = IDX.read_text(encoding="utf-8")
bak  = IDX.with_suffix(".html.bak")
s = orig; changed = False

if not re.search(r"<title>\s*Paste12\s*</title>", s, flags=re.I):
    if re.search(r"<title>.*?</title>", s, flags=re.S|re.I):
        s = re.sub(r"<title>.*?</title>", "<title>Paste12</title>", s, count=1, flags=re.S|re.I)
    else:
        s = re.sub(r"</head>", "  <title>Paste12</title>\n</head>", s, count=1, flags=re.I)
    changed = True

if not re.search(r'<h1[^>]*class="[^"]*\bbrand\b[^"]*"[^>]*>\s*Paste12\s*</h1>', s, flags=re.I):
    def _fix_h1(h):
        if re.search(r'class="', h, flags=re.I):
            h = re.sub(r'class="([^"]*)"', lambda m: f'class="{m.group(1)} brand"', h, count=1, flags=re.I)
        else:
            h = h.replace("<h1", '<h1 class="brand"')
        return re.sub(r">(.*?)</h1>", ">Paste12</h1>", h, flags=re.S)
    s2, n = re.subn(r"(<header\b[^>]*>.*?)(<h1\b[^>]*>.*?</h1>)(.*?</header>)",
                    lambda m: m.group(1)+_fix_h1(m.group(2))+m.group(3),
                    s, flags=re.S|re.I)
    if n: s, changed = s2, True
    else:
        s2, n = re.subn(r"(<header\b[^>]*>)", r'\1\n  <h1 class="brand">Paste12</h1>', s, flags=re.I)
        if n: s, changed = s2, True
        else:
            s2, n = re.subn(r"(<body\b[^>]*>)", r'\1\n<header><h1 class="brand">Paste12</h1></header>', s, flags=re.I)
            if n: s, changed = s2, True

if not re.search(r'<div\s+id="tagline"\b', s, flags=re.I):
    s2, n = re.subn(
        r'(<header\b[^>]*>.*?<h1\b[^>]*class="[^"]*\bbrand\b[^"]*"[^>]*>.*?</h1>)',
        r'\1\n  <div id="tagline">Reta a un amigo · Dime un secreto · Confiesa algo</div>',
        s, flags=re.S|re.I
    )
    if n: s, changed = s2, True

if not changed:
    print("OK: ya tenía title/brand/tagline"); sys.exit(0)
if not bak.exists():
    shutil.copyfile(IDX, bak)
IDX.write_text(s, encoding="utf-8")
print("patched: title/brand/tagline (backup creado)")
PY
chmod +x tools/ensure_brand_title.py

# 4) Ejecutar parches (idempotentes)
python tools/append_likes_guard_min.py
python tools/ensure_brand_title.py || true

# 5) Commit + push
git add wsgiapp/__init__.py backend/static/index.html tools/append_likes_guard_min.py tools/ensure_brand_title.py
git commit -m "feat(likes): dedupe 1x persona (append-only) + fix(ui): title Paste12/h1.brand/tagline"
git push

echo
echo "✓ Reaplicado y pusheado. Tras el deploy, corre: tools/smoke_after_deploy.sh <BASE>"
