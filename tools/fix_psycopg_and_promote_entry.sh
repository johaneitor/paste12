#!/usr/bin/env bash
set -euo pipefail

# 1) Asegurar driver de Postgres en requirements.txt (psycopg2-binary)
REQ=requirements.txt
touch "$REQ"
if ! grep -Eiq '^(psycopg2-binary|psycopg(\[binary\])?)' "$REQ"; then
  echo "psycopg2-binary~=2.9" >> "$REQ"
  echo "[+] Agregado psycopg2-binary a $REQ"
else
  echo "[=] $REQ ya contiene psycopg*"
fi

# 2) Normalizar DATABASE_URL en render_entry.py (si existe)
fix_dburl_py='
import os, re, io, sys
p = "render_entry.py"
if not os.path.exists(p):
    print("[i] No existe render_entry.py (se usará el wsgiapp bridge).")
    sys.exit(0)
s = open(p,"r",encoding="utf-8").read()
if "def _normalize_database_url(" not in s:
    s += """

# --- bootstrap DB URL normalize (idempotente) ---
def _normalize_database_url(url: str|None):
    if not url: return url
    # Corrige esquema antiguo de Heroku: postgres:// -> postgresql://
    if url.startswith("postgres://"):
        return "postgresql://" + url[len("postgres://"):]
    return url

try:
    import os
    if "SQLALCHEMY_DATABASE_URI" in app.config:
        app.config["SQLALCHEMY_DATABASE_URI"] = _normalize_database_url(app.config.get("SQLALCHEMY_DATABASE_URI"))
    else:
        _env = _normalize_database_url(os.environ.get("DATABASE_URL"))
        if _env:
            app.config["SQLALCHEMY_DATABASE_URI"] = _env
    # create_all best-effort
    try:
        from backend import db
        with app.app_context():
            db.create_all()
    except Exception:
        pass
except Exception:
    pass
"""
    open(p,"w",encoding="utf-8").write(s)
    print("[+] render_entry.py: añadida normalización de DATABASE_URL y create_all() best-effort.")
else:
    print("[=] render_entry.py ya tenía normalizador de DATABASE_URL.")
'
python - <<PY
${fix_dburl_py}
PY

# 3) Commit & push
git add -A
git commit -m "fix: add psycopg2-binary and DB URL normalize; best-effort create_all" || true
git push -u --force-with-lease origin "$(git rev-parse --abbrev-ref HEAD)"

cat <<'MSG'

[✓] Cambios enviados.

Siguientes pasos en Render:
  1) Verifica que exista la variable de entorno DATABASE_URL (Postgres).
     - Si empieza con 'postgres://', igual sirve: el código la corrige a 'postgresql://'.
  2) No cambies el Start Command (puede seguir como wsgiapp:app).
     El bridge intentará importar render_entry:app; con el driver ya instalado, debería tomar el entry real.
  3) Redeploy. Cuando esté arriba, corre:

     bash tools/remote_probe_wsgiapp.sh

Esperado:
  - /api/diag/import -> "import_path":"render_entry:app", "fallback": false
  - /api/diag/urlmap -> /api/notes GET/POST presentes (y tus endpoints de interactions)
  - /api/notes GET    -> 200 []
  - /api/ix…          -> 200/JSON (si tienes notas creadas)
MSG
