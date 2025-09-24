#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"

TARGET="wsgiapp/__init__.py"
[ -f "$TARGET" ] || { echo "[!] No existe $TARGET (bridge V2)"; exit 1; }

echo "[+] Backup de $TARGET"
cp -f "$TARGET" "$TARGET.bak.$(date +%s)"

echo "[+] Parchando bridge para forzar DB real y desactivar shim por defecto…"
python - "$TARGET" <<'PY'
import io, re, sys
p = sys.argv[1]
s = open(p, 'r', encoding='utf-8').read()

# 1) En _ensure_db(): asegura que use DATABASE_URL si existe, corrige postgres:// a postgresql://
s = re.sub(
    r"def _ensure_db\(\):(.|\n)*?return _db, _Note",
    r'''def _ensure_db():
    """Inicializa SQLAlchemy ligado a ESTA app y crea tablas. Devuelve (db, Note) o (None, None) si falla."""
    global _db, _Note
    if _db is not None and _Note is not None:
        return _db, _Note
    try:
        from flask_sqlalchemy import SQLAlchemy
    except Exception:
        return None, None
    try:
        # Forzar DATABASE_URL si está definida
        import os
        uri = os.environ.get("DATABASE_URL") or os.environ.get("SQLALCHEMY_DATABASE_URI")
        if uri:
            if uri.startswith("postgres://"):
                uri = "postgresql://" + uri[len("postgres://"):]
            app.config["SQLALCHEMY_DATABASE_URI"] = uri
        # Config por si acaso
        app.config.setdefault("SQLALCHEMY_TRACK_MODIFICATIONS", False)

        _db = SQLAlchemy(app)
        class Note(_db.Model):
            __tablename__ = "note"
            id = _db.Column(_db.Integer, primary_key=True)
            text = _db.Column(_db.Text, nullable=False)
            timestamp = _db.Column(_db.DateTime, nullable=False, index=True)
            expires_at = _db.Column(_db.DateTime, nullable=False, index=True)
            likes = _db.Column(_db.Integer, default=0, nullable=False)
            views = _db.Column(_db.Integer, default=0, nullable=False)
            reports = _db.Column(_db.Integer, default=0, nullable=False)
            author_fp = _db.Column(_db.String(64), nullable=False, default="noctx", index=True)
        _Note = Note
        try:
            with app.app_context():
                _db.create_all()
        except Exception:
            pass
        return _db, _Note
    except Exception:
        _db, _Note = None, None
        return None, None''',
    s, count=1, flags=re.DOTALL
)

# 2) Desactivar shim por defecto: solo usar si BRIDGE_ALLOW_SHIM=1
s = re.sub(
    r"_mem = \{[^}]+\}\s+# shim en memoria.*",
    r'''_mem = {"seq": 0, "items": []}  # shim en memoria
def _shim_enabled() -> bool:
    import os
    return os.environ.get("BRIDGE_ALLOW_SHIM","0").strip() in ("1","true","yes")''',
    s
)

# 3) En handlers, no caer a shim salvo que esté habilitado
s = re.sub(
    r"# cae a shim en memoria\s+pass\s+        # Shim en memoria",
    r"# cae a shim en memoria\n                pass\n        # Shim en memoria (si está habilitado)",
    s
)
s = s.replace(
    "        # Shim en memoria",
    "        # Shim en memoria (si está habilitado)"
)

s = s.replace(
    "        try:\n            page = 1",
    "        if not _shim_enabled():\n            return jsonify(ok=False, error=\"list_failed\", detail=str(e)), 500\n        try:\n            page = 1"
)

s = s.replace(
    "        # Shim en memoria\n        try:\n            _mem[\"seq\"] += 1",
    "        if not _shim_enabled():\n            return jsonify(ok=False, error=\"create_failed\", detail=\"DB unavailable and shim disabled\"), 500\n        # Shim en memoria\n        try:\n            _mem[\"seq\"] += 1"
)

open(p, 'w', encoding='utf-8').write(s)
print("[OK] Bridge actualizado: usa DATABASE_URL, corrige postgres:// y desactiva shim salvo BRIDGE_ALLOW_SHIM=1")
PY

echo "[+] Commit & push"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
git add -A
git commit -m "bridge: force real DB (DATABASE_URL), fix postgres scheme; shim disabled by default" || true
git push -u --force-with-lease origin "$BRANCH"

cat <<'EON'

Next steps en Render:
1) Environ → añade/valida DATABASE_URL (Postgres). Si empieza con 'postgres://', sirve igual: el bridge la corrige a 'postgresql://'.
2) (Opcional) Mientras pruebas sin DB, puedes permitir el shim: BRIDGE_ALLOW_SHIM=1
3) Redeploy el servicio.

Verificación:
  curl -s https://paste12-rmsk.onrender.com/api/debug-urlmap | jq .
  curl -i -s 'https://paste12-rmsk.onrender.com/api/notes?page=1' | sed -n '1,80p'
  curl -i -s -X POST -H 'Content-Type: application/json' -d '{"text":"remote-db","hours":24}' \
       https://paste12-rmsk.onrender.com/api/notes | sed -n '1,160p'

Persistencia:
- Si usas DB real, la nota persiste tras redeploy.
- Si usas shim (BRIDGE_ALLOW_SHIM=1), se pierde al redeploy.

EON
